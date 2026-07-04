-module(ebb_dhcp_pool_mem).
-moduledoc """
This module stores DHCP leases strictly in memory. It does not write them out to disk.

It should be used only for demo purposes.
""".
-behaviour(gen_server).

%% TODO:
%%     The API for this module should probably an API that roughly maps onto
%%     the client RPCs, e.g.:
%%         accept_offer/1
%%         	 --> replies with lease (lease is in state ACTIVE)
%%         decline_offer/1
%%           --> does NOT reply, but marks the IP as 'bad'

-include("dhcp.hrl").

%% API
-export([
    start_link/0,
    get_offer/1,
    create_offer/1,
    accept_offer/1,
    dump/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get_offer(dhcp_message()) -> {ok, dhcp_lease()} | {error, term()}.
get_offer(Msg) ->
    gen_server:call(?MODULE, {get_offer, Msg}).

-doc """
Retrieve/extend an existing DHCP lease, or create a new one. Identifier is
treated as an opaque object, as clients may send:
   - UUID (Option 97)
   - Arbitrary string identifier OR MAC Address (Option 61)
   - MAC Address (ChAddr)
""".
-spec create_offer(dhcp_message()) -> {ok, dhcp_lease()} | {error, term()}.
create_offer(Msg) ->
    gen_server:call(?MODULE, {create_offer, Msg}).

-spec accept_offer(dhcp_message()) -> {ok, dhcp_lease()} | {error, term()}.
accept_offer(Msg) ->
    gen_server:call(?MODULE, {accept_offer, Msg}).

dump() ->
    gen_server:call(?MODULE, dump).

init([]) ->
    {ok, #{
        pool => [],
        range => ebb_config:get([dhcp, range])
    }}.

handle_call({get_offer, Msg}, _From, #{pool := Pool} = State) ->
    ClientID = Msg#dhcp_message.chaddr,
    Reply =
        case lists:keyfind(ClientID, #dhcp_lease.client_id, Pool) of
            false ->
                {error, no_such_offer};
            Lease ->
                {ok, Lease}
        end,
    {reply, Reply, State};
handle_call({create_offer, Msg}, _From, State) ->
    #{pool := Pool, range := Range} = State,
    ClientID = Msg#dhcp_message.chaddr,
    Options = Msg#dhcp_message.options,
    LeaseDuration =
        case proplists:get_value(lease_time, Options, false) of
            Value when is_integer(Value) ->
                % Ensure that we're getting an integer from the client message,
                % otherwise give them the default
                Value;
            _ ->
                ebb_config:get([dhcp, lease_seconds])
        end,
    % See next_ip/2 deficiencies
    {ok, ClientIP} = next_ip(Pool, Range),
    Lease = #dhcp_lease{
        ip = ClientIP,
        client_id = ClientID,
        subnet_mask = to_mask(Range),
        state = offered,
        expiration = erlang:send_after(
            ebb_config:get([dhcp, offer_timeout_seconds]) * 1000,
            self(),
            {expire, ClientID}
        ),
        duration = LeaseDuration
    },
    Reply = {ok, Lease},
    {reply, Reply, State#{pool => [Lease | Pool]}};
handle_call({accept_offer, Msg}, _From, #{pool := Pool} = State) ->
    ClientID = Msg#dhcp_message.chaddr,
    case lists:keyfind(ClientID, #dhcp_lease.client_id, Pool) of
        false ->
            {reply, {error, no_offer}, State};
        Lease ->
            maybe_cancel_timer(Lease#dhcp_lease.expiration),
            ActiveLease = Lease#dhcp_lease{
                state = active,
                expiration = erlang:send_after(
                    Lease#dhcp_lease.duration * 1000, self(), {expire, ClientID}
                )
            },
            Pool1 = lists:keyreplace(
                ClientID, #dhcp_lease.client_id, Pool, ActiveLease
            ),
            {reply, {ok, ActiveLease}, State#{pool => Pool1}}
    end;
handle_call(dump, _From, #{pool := Pool} = State) ->
    {reply, Pool, State};
handle_call(_Request, _From, State) ->
    {reply, {error, ignored}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({expire, ID}, #{pool := Pool} = State) ->
    case lists:keyfind(ID, #dhcp_lease.client_id, Pool) of
        false ->
            logger:warning("Expire fired for unknown client ~p", [ID]),
            {noreply, State};
        Lease ->
            case Lease#dhcp_lease.state of
                offered ->
                    logger:notice("Offer timed out for ~p", [ID]),
                    Pool1 = lists:keydelete(ID, #dhcp_lease.client_id, Pool),
                    {noreply, State#{pool => Pool1}};
                _ ->
                    logger:notice("Expiring lease for ~p", [ID]),
                    ExpiredLease = Lease#dhcp_lease{
                        state = expired, expiration = undefined
                    },
                    Pool1 = lists:keyreplace(
                        ID, #dhcp_lease.client_id, Pool, ExpiredLease
                    ),
                    {noreply, State#{pool => Pool1}}
            end
    end;
handle_info(_Info, State) ->
    {noreply, State}.

%% Internal functions

% Current deficiencies:
% 	- Does not harvest expired IPs
% 	- Does not allow clients to use Option 50 to request an IP
next_ip(Pool, Range) ->
    {Start, End, _Prefix} = Cidr = inet_cidr:parse(Range),
    Low = ip_to_int(Start) + 2,
    Bcast = ip_to_int(End),
    Used = lists:sort([
        ip_to_int(IP)
     || #dhcp_lease{ip = IP, state = S} <- Pool,
        S =/= expired,
        inet_cidr:contains(Cidr, IP)
    ]),
    scan(Used, Low, Bcast).

ip_to_int({A, B, C, D}) ->
    <<N:32>> = <<A:8, B:8, C:8, D:8>>,
    N.
int_to_ip(N) ->
    <<A:8, B:8, C:8, D:8>> = <<N:32>>,
    {A, B, C, D}.

scan(_, Cursor, Bcast) when Cursor >= Bcast -> {error, full};
scan([], Cursor, _) -> {ok, int_to_ip(Cursor)};
scan([H | _], Cursor, _) when H > Cursor -> {ok, int_to_ip(Cursor)};
scan([H | T], Cursor, Bcast) -> scan(T, max(Cursor, H + 1), Bcast).

to_mask(Range) ->
    {_Begin, _End, Prefix} = inet_cidr:parse(Range),
    prefix_to_mask(Prefix).
prefix_to_mask(Len) when Len >= 0, Len =< 32 ->
    <<M:32>> = <<(bnot ((1 bsl (32 - Len)) - 1)):32>>,
    {M bsr 24, (M bsr 16) band 16#FF, (M bsr 8) band 16#FF, M band 16#FF}.

maybe_cancel_timer(undefined) ->
    ok;
maybe_cancel_timer(Ref) when is_reference(Ref) ->
    erlang:cancel_timer(Ref).

-module(ebb_dhcp_pool_mem).
%%-doc """
%%This module stores DHCP leases strictly in memory. It does not write them out to disk.
%%
%%It should be used only for demo purposes.
%%""".
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
    dump/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get_offer(dhcp_message()) -> {ok, inet:ip4_address()}.
get_offer(Msg) ->
    gen_server:call(?MODULE, {get_offer, Msg}).

%-doc """
%Retrieve/extend an existing DHCP lease, or create a new one. Identifier is
%treated as an opaque object, as clients may send:
%	- UUID (Option 97)
%	- Arbitrary string identifier OR MAC Address (Option 61)
%	- MAC Address (ChAddr)
%""".
-spec create_offer(dhcp_message()) -> {ok, inet:ip4_address()}.
create_offer(Msg) ->
    gen_server:call(?MODULE, {create_offer, Msg}).

dump() ->
    gen_server:call(?MODULE, dump).

init([]) ->
    {ok, #{
        pool => [],
        range => ?DEFAULT_CIDR_RANGE
    }}.

%handle_call({create_offer, Identifier, LeaseDuration}, _From, State) ->
handle_call({get_offer, Msg}, _From, #{pool := Pool} = State) ->
    ClientID = Msg#dhcp_message.chaddr,
    Result = lists:keyfind(ClientID, #dhcp_lease.client_id, Pool),
    {reply, Result, State};
handle_call({create_offer, Msg}, _From, State) ->
    #{pool := Pool, range := Range} = State,
    ClientID = Msg#dhcp_message.chaddr,
    Options = Msg#dhcp_message.options,
    LeaseDuration =
        case proplists:get_value(lease_time, Options, false) of
            false ->
                ?DEFAULT_LEASE_SECONDS;
            Value ->
                Value
        end,
    % See next_ip/2 deficiencies
    {ok, ClientIP} = next_ip(Pool, Range),
    Lease = #dhcp_lease{
        ip = ClientIP,
        client_id = ClientID,
        subnet_mask = to_mask(Range),
        state = offered,
        expiration = erlang:send_after(
            ?DEFAULT_OFFER_TIMEOUT_SECONDS * 1000, self(), {expire, ClientID}
        ),
        duration = LeaseDuration
    },
    {reply, Lease, State#{pool => [Lease | Pool]}};
%handle_call({create_offer, DHCPMsg}, _From, State) ->
%    #{pool := Pool, range := Range} = State,
%    {NewLease, NewPool} =
%        case lists:keyfind(Identifier, #dhcp_lease.client_id, Pool) of
%            false ->
%                {Lease, Pool1} = create_lease(
%                    Identifier, LeaseDuration, Range, Pool
%                ),
%                {Lease, Pool1};
%            Lease ->
%                % TODO: Maybe this needs to be handled elsewhere. We need to
%                % pass forward the ACK for a DHCP offer, for instance
%                {L, T} =
%                    case Lease#dhcp_lease.state of
%                        active ->
%                            % Renew the timer
%                            ExpireTimer = Lease#dhcp_lease.expiration,
%                            erlang:cancel_timer(ExpireTimer),
%                            Lease1 = Lease#dhcp_lease{expiration = LeaseDuration},
%                            Pool1 = lists:keyreplace(
%                                Identifier, #dhcp_lease.client_id, Pool, Lease1
%                            ),
%                            {Lease1, Pool1};
%                        expired ->
%                            % Re-activate
%                            Lease1 = Lease#dhcp_lease{state = active},
%                            Pool1 = lists:keyreplace(
%                                Identifier, #dhcp_lease.client_id, Pool, Lease1
%                            ),
%                            {Lease1, Pool1};
%                        released ->
%                            % Re-activate
%                            Lease1 = Lease#dhcp_lease{state = active},
%                            Pool1 = lists:keyreplace(
%                                Identifier, #dhcp_lease.client_id, Pool, Lease1
%                            ),
%                            {Lease1, Pool1}
%                    end,
%                {L, T}
%        end,
%    {reply, {ok, NewLease}, State#{pool => NewPool}};
handle_call(dump, _From, #{pool := Pool} = State) ->
    {reply, Pool, State};
handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({expire, ID}, #{pool := Pool} = State) ->
    % This should crash if we don't find the key..
    Lease = lists:keyfind(ID, #dhcp_lease.client_id, Pool),
    S = Lease#dhcp_lease.state,
    case S of
        offered ->
            logger:notice("Offer timed out for ~p", [ID]),
            Pool1 = lists:keydelete(ID, #dhcp_lease.client_id, Pool),
            {noreply, State#{pool => Pool1}};
        _ ->
            logger:notice("Expiring lease for ~p", [ID]),
            ExpiredLease = Lease#dhcp_lease{
                state = expired, expiration = undefined
            },
            Pool1 = lists:keyreplace(ID, #dhcp_lease.client_id, Pool, ExpiredLease),
            {noreply, State#{pool => Pool1}}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions

% Current deficiencies:
% 	- Does not harvest expired IPs
% 	- Does not allow clients to use Option 50 to request an IP
next_ip(Pool, Range) ->
    {Start, End, Prefix} = inet_cidr:parse(Range),
    Low = ip_to_int(Start) + 1,
    Bcast = ip_to_int(End),
    Used = lists:sort([
        ip_to_int(IP)
     || #dhcp_lease{ip = IP} <- Pool,
        inet_cidr:contains({Start, End, Prefix}, IP)
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

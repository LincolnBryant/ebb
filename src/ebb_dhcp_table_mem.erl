%%% % @format

-module(ebb_dhcp_table_mem).
%%-doc """
%%This module stores DHCP leases strictly in memory. It does not write them out to disk.
%%
%%It should be used only for demo purposes.
%%""".
-behaviour(gen_server).

%% TODO:
%%     The API for this module should probably an API that roughly maps onto the client RPCs, e.g.:
%%         create_offer/1  (via DHCPDISCOVER)
%%           --> replies with offer (lease is in state OFFER)
%%         accept_offer/1
%%         	 --> replies with lease (lease is in state ACTIVE)
%%         decline_offer/1
%%           --> does NOT reply, but marks the IP as 'bad'

-include("dhcp.hrl").

%% API
-export([
    start_link/0,
    get_or_create/2,
    get_or_create/1,
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

%-doc """
%Retrieve/extend an existing DHCP lease, or create a new one. Identifier is
%treated as an opaque object, as clients may send:
%	- UUID (Option 97)
%	- Arbitrary string identifier OR MAC Address (Option 61)
%	- MAC Address (ChAddr)
%""".
-spec get_or_create(client_id()) -> {ok, inet:ip4_address()}.
get_or_create(Identifier) ->
    get_or_create(Identifier, ?DEFAULT_LEASE_SECONDS).

-spec get_or_create(client_id(), non_neg_integer()) -> {ok, inet:ip4_address()}.
get_or_create(Identifier, LeaseDuration) ->
    gen_server:call(?MODULE, {get_or_create, Identifier, LeaseDuration}).

dump() ->
    gen_server:call(?MODULE, dump).

init([]) ->
    Table = [],
    Range = ?DEFAULT_CIDR_RANGE,
    {ok, #{
        table => Table,
        range => Range,
        next_ip => next_ip(Range, Table)
    }}.

handle_call({get_or_create, Identifier, LeaseDuration}, _From, State) ->
    #{table := Table, range := Range} = State,
    {NewLease, NewTable} =
        case lists:keyfind(Identifier, #dhcp_lease.client_id, Table) of
            false ->
                {Lease, Table1} = create_lease(
                    Identifier, LeaseDuration, Range, Table
                ),
                {Lease, Table1};
            Lease ->
                % TODO: Maybe this needs to be handled elsewhere. We need to
                % pass forward the ACK for a DHCP offer, for instance
                {L, T} =
                    case Lease#dhcp_lease.state of
                        active ->
                            % Renew the timer
                            ExpireTimer = Lease#dhcp_lease.expiration,
                            erlang:cancel_timer(ExpireTimer),
                            Lease1 = Lease#dhcp_lease{expiration = LeaseDuration},
                            Table1 = lists:keyreplace(
                                Identifier, #dhcp_lease.client_id, Table, Lease1
                            ),
                            {Lease1, Table1};
                        expired ->
                            % Re-activate
                            Lease1 = Lease#dhcp_lease{state = active},
                            Table1 = lists:keyreplace(
                                Identifier, #dhcp_lease.client_id, Table, Lease1
                            ),
                            {Lease1, Table1};
                        released ->
                            % Re-activate
                            Lease1 = Lease#dhcp_lease{state = active},
                            Table1 = lists:keyreplace(
                                Identifier, #dhcp_lease.client_id, Table, Lease1
                            ),
                            {Lease1, Table1}
                    end,
                {L, T}
        end,
    {reply, {ok, NewLease}, State#{table => NewTable}};
handle_call(dump, _From, #{table := Table} = State) ->
    {reply, Table, State};
handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({expire, ID}, #{table := Table} = State) ->
    % This should crash if we don't find the key..
    Lease = lists:keyfind(ID, #dhcp_lease.client_id, Table),
    S = Lease#dhcp_lease.state,
    case S of
        offered ->
            logger:notice("Offer timed out for ~p", [ID]),
			Table1 = lists:keydelete(ID, #dhcp_lease.client_id, Table),
			{noreply, State#{table => Table1}};
        _ ->
            logger:notice("Expiring lease for ~p", [ID]),
			ExpiredLease = Lease#dhcp_lease{state = expired, expiration = undefined},
			Table1 = lists:keyreplace(ID, #dhcp_lease.client_id, Table, ExpiredLease),
			{noreply, State#{table => Table1}}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions

create_lease(Identifier, LeaseDuration, Range, Table) ->
    {ok, IP} = next_ip(Range, Table),
    Lease = #dhcp_lease{
        ip = IP,
        client_id = Identifier,
        state = offered,
        expiration = erlang:send_after(
            ?DEFAULT_OFFER_TIMEOUT_SECONDS * 1000, self(), {expire, Identifier}
        ),
        duration = LeaseDuration
    },
    {Lease, [Lease | Table]}.

% This does NOT handle the case where we can harvest expired IPs from the
% table. Need to fix!
next_ip(Range, Table) ->
    {Start, End, Prefix} = inet_cidr:parse(Range),
    Low = ip_to_int(Start) + 1,
    Bcast = ip_to_int(End),
    Used = lists:sort([
        ip_to_int(IP)
     || #dhcp_lease{ip = IP} <- Table,
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

-module(ebb_dhcpd).
-behaviour(gen_server).
-doc """
A simple stub DHCP server. This module deliberately eschews RFC 2131, RFC 2132,
RFC 8415 and the rest of the DHCPd ecosystem. We instead focus on the minimum
compatible subset of DHCP needed to reliably PXE boot Linux and FreeBSD
servers.
""".

%% API
-export([
    start_link/0,
    handle_request/3
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

handle_request(Address, Port, Msg) ->
    gen_server:call(?MODULE, {handle_request, Address, Port, Msg}).

init([]) ->
    {ok, #{}}.

handle_call({handle_request, _Address, _Port, Msg}, _From, State) ->
    Decoded = ebb_dhcp_packet:decode(Msg),
    logger:notice("Decoded DHCPd packet: ~p", [Decoded]),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions

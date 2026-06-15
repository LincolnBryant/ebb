-module(ebb_dhcpd).
-behaviour(gen_server).
-doc """
A simple stub DHCP server. This module does not fully implement RFC 2131, RFC
2132, RFC 8415 and the rest of the DHCPd ecosystem. We instead focus on the
minimum compatible subset of DHCP needed to reliably PXE boot Linux and FreeBSD
servers.
""".

%% API
-export([
    start_link/0
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

init([]) ->
    {ok, Socket} = gen_udp:open(67, [{active, once}, binary]),
    {ok, #{socket => Socket}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({udp, Socket, _Addr, _Port, Packet}, State) ->
	DHCPMsg = ebb_dhcp_packet:decode(Packet), 
	logger:notice("Got DHCP message: ~p", [DHCPMsg]),
	% Rearm the socket
    inet:setopts(Socket, [{active, once}]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

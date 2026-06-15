-module(ebb_dhcpd).
-behaviour(gen_server).
-doc """
A simple stub DHCP server. This module does not fully implement RFC 2131, RFC
2132, RFC 8415 and the rest of the DHCPd ecosystem. We instead focus on the
minimum compatible subset of DHCP needed to reliably PXE boot Linux and FreeBSD
servers.
""".

-include("dhcp.hrl").

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
    {ok, 
	 #{
	   socket => Socket
	  }
	}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({udp, Socket, _Addr, _Port, Packet}, #{ lease := Leases } = State) ->
	NewLeases = route(ebb_dhcp_packet:decode(Packet), Leases),
    inet:setopts(Socket, [{active, once}]),
    {noreply, State#{ leases => NewLeases }}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

route(#dhcp_message{ op = bootrequest } = DHCPMsg, Leases) ->
	{Reply, NewLeases} = maybe_lease(DHCPMsg, Leases),
	% TODO send reply
	NewLeases;
route(_, Leases) -> 
	logger:debug("Not implemented: Won't handle bootreply messages"),
	Leases.


maybe_lease(Msg, LeaseTable) -> 
	Options = Msg#dhcp_message.options,
	MacAddr = Msg#dhcp_message.chaddr,
	MsgType = proplists:get_val(message_type),
	case MsgType of
		dhcpdiscover ->
			Lease = create_or_return_lease(MacAddr),
			{todo, LeaseTable};
		_ ->
			logger:debug("Not implemented"),
			{undefined, LeaseTable}
	end.

create_or_return_lease(MacAddr) -> 
	ok.


%% This all needs to be redone.
%% Lease table should be a separate process and we send mesages to it.
%% We need to determine all of the terminating states for when a reply is sent
%% Thread through stuff correctly.

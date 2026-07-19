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
    start_link/2,
    % for testing
    route_msg/2
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

start_link(Interface, Cidr) ->
    gen_server:start_link(?MODULE, [Interface, Cidr], []).

init([Interface, _Cidr]) ->
	% This can potentially fail if an interface doesn't exist
    {ok, AllAddrs} = inet:getifaddrs(),
    case proplists:get_value(Interface, AllAddrs, false) of 
		false ->
			logger:critical("Cannot find interface ~p", [Interface]),
			{stop, shutdown};
		IfOpts -> 
			Addr = proplists:get_value(addr, IfOpts),
			{ok, Socket} = gen_udp:open(?DHCP_PORT, [
				{ip, Addr}, {active, once}, {broadcast, true}, binary
			]),
			{ok, #{
				socket => Socket
			}}
	end.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

%                    ┌────────────────┐
%       power on ──► │     INIT       │ ◄── NAK / lease expired / DECLINE / RELEASE
%                    └───────┬────────┘
%                            │ DHCPDISCOVER
%                            ▼
%                    ┌────────────────┐
%                    │   SELECTING    │
%                    └───────┬────────┘
%                            │ DHCPREQUEST (broadcast)
%                            ▼
%                    ┌────────────────┐
%                    │   REQUESTING   │──── NAK ───────► (restart)
%                    └───────┬────────┘
%                            │ ACK
%                            ▼
%                     ┌──────────────┐
%                     │    BOUND     │
%                     └──────┬───────┘
%                            │ T1
%                            ▼
%                     ┌──────────────┐
%       ACK ◄──────── │   RENEWING   │
%     (BOUND)         └──────┬───────┘
%                            │ T2
%                            ▼
%                     ┌──────────────┐
%       ACK ◄──────── │  REBINDING   │
%     (BOUND)         └──────┬───────┘
%                            │ lease expires
%                            ▼
%                          INIT

handle_info({udp, Socket, _Addr, _Port, Packet}, State) ->
    % Rearm the socket for another message
    inet:setopts(Socket, [{active, once}]),
    try
        Msg = ebb_dhcp_packet:decode(Packet),
        % Consume the packet and send a reply as a side effect, as necessary
        route_msg(Msg, Socket)
    catch
        error:function_clause:_Stacktrace ->
            logger:debug("Possibly malformed packet: ~p", [Packet])
    end,
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

route_msg(Msg = #dhcp_message{op = bootrequest, options = Options}, Socket) ->
    MsgType = proplists:get_value(message_type, Options),
    logger:notice("DHCP ~p from ~p (xid=~.16B)", [
        MsgType, Msg#dhcp_message.chaddr, Msg#dhcp_message.xid
    ]),
    case MsgType of
        dhcpdiscover ->
            OfferLease =
                case ebb_dhcp_pool_mem:get_offer(Msg) of
                    {error, no_such_offer} ->
                        {ok, NewLease} = ebb_dhcp_pool_mem:create_offer(Msg),
                        NewLease;
                    {ok, ExistingLease} ->
                        ExistingLease
                end,
            send_offer(Msg, OfferLease, Socket);
        dhcprequest ->
            case ebb_dhcp_pool_mem:accept_offer(Msg) of
                {error, Reason} ->
                    logger:notice("NAK reason: ~p, pool: ~p", [
                        Reason, ebb_dhcp_pool_mem:dump()
                    ]),
                    send_nak(Msg, Socket);
                {ok, Lease} ->
                    send_ack(Msg, Lease, Socket)
            end;
        _ ->
            % TODO: Handle other message types
            ok
    end;
route_msg(_Msg, _) ->
    logger:debug("Discarding non-implemented message type").

send_offer(DiscoverMsg, Offer, Socket) ->
    % Retrieve fields from the original message
    #dhcp_message{
        xid = Xid,
        chaddr = ChAddr,
        giaddr = GiAddr,
        htype = HType,
        hlen = HLen,
        flags = Flags
    } = DiscoverMsg,
    % Pull the client IP out of the offer
    #dhcp_lease{
        ip = ClientIP,
        subnet_mask = SubnetMask,
        duration = Duration
    } = Offer,
    ServerIP = server_ip(Socket),
    % Create the options list
    Options = [
        {subnet_mask, SubnetMask},
        {lease_time, Duration},
        {message_type, dhcpoffer},
        {server_id, ServerIP}
    ],
    OfferMsg = #dhcp_message{
        op = bootreply,
        htype = HType,
        hlen = HLen,
        hops = 0,
        xid = Xid,
        secs = 0,
        flags = [broadcast],

        ciaddr = {0, 0, 0, 0},
        yiaddr = ClientIP,
        siaddr = ServerIP,
        giaddr = GiAddr,
        chaddr = ChAddr,

        sname = <<>>,
        file = <<>>,

        options = Options
    },
    OfferPacket = ebb_dhcp_packet:encode(OfferMsg),
    case Flags of
        [broadcast] ->
            logger:notice("Broadcasting OFFER ~p to ~p", [ClientIP, ChAddr]),
            send_broadcast(Socket, OfferPacket);
        [] ->
            send_unicast(Socket, OfferPacket)
    end.

send_ack(RequestMsg, Lease, Socket) ->
    #dhcp_message{
        xid = Xid,
        chaddr = ChAddr,
        giaddr = GiAddr,
        htype = HType,
        hlen = HLen
    } = RequestMsg,
    #dhcp_lease{
        ip = ClientIP,
        subnet_mask = SubnetMask,
        duration = Duration
    } = Lease,
    ServerIP = server_ip(Socket),
    Options = [
        {subnet_mask, SubnetMask},
        {lease_time, Duration},
        {message_type, dhcpack},
        {server_id, ServerIP}
    ],
    AckMsg = #dhcp_message{
        op = bootreply,
        htype = HType,
        hlen = HLen,
        hops = 0,
        xid = Xid,
        secs = 0,
        flags = [broadcast],
        ciaddr = {0, 0, 0, 0},
        yiaddr = ClientIP,
        siaddr = ServerIP,
        giaddr = GiAddr,
        chaddr = ChAddr,
        sname = <<>>,
        file = <<>>,
        options = Options
    },
    logger:notice("Sending ACK ~p to ~p", [ClientIP, ChAddr]),
    AckPacket = ebb_dhcp_packet:encode(AckMsg),
    send_broadcast(Socket, AckPacket).

send_nak(RequestMsg, Socket) ->
    #dhcp_message{
        xid = Xid,
        chaddr = ChAddr,
        giaddr = GiAddr,
        htype = HType,
        hlen = HLen
    } = RequestMsg,
    ServerIP = server_ip(Socket),
    Options = [
        {message_type, dhcpnak},
        {server_id, ServerIP}
    ],
    NakMsg = #dhcp_message{
        op = bootreply,
        htype = HType,
        hlen = HLen,
        hops = 0,
        xid = Xid,
        secs = 0,
        flags = [broadcast],
        ciaddr = {0, 0, 0, 0},
        yiaddr = {0, 0, 0, 0},
        siaddr = ServerIP,
        giaddr = GiAddr,
        chaddr = ChAddr,
        sname = <<>>,
        file = <<>>,
        options = Options
    },
    logger:notice("Sending NAK to ~p", [ChAddr]),
    NakPacket = ebb_dhcp_packet:encode(NakMsg),
    send_broadcast(Socket, NakPacket).

server_ip(Socket) ->
    case inet:sockname(Socket) of
        {ok, {{0, 0, 0, 0}, _}} ->
            guess_server_ip();
        {ok, {IP, _}} ->
            IP
    end.

guess_server_ip() ->
    Cidr = inet_cidr:parse(ebb_config:get([dhcp, range])),
    {Start, _End, _Prefix} = Cidr,
    {ok, Addrs} = inet:getifaddrs(),
    case
        [
            IP
         || {_If, Opts} <- Addrs,
            {addr, IP} <- Opts,
            tuple_size(IP) =:= tuple_size(Start),
            inet_cidr:contains(Cidr, IP)
        ]
    of
        [First | _] -> First;
        [] -> Start
    end.

send_broadcast(Socket, Packet) ->
    Bcast = subnet_broadcast(),
    gen_udp:send(Socket, Bcast, 68, Packet).

% TODO
send_unicast(Socket, Packet) ->
    ok.

subnet_broadcast() ->
    {_Start, End, _Prefix} = inet_cidr:parse(ebb_config:get([dhcp, range])),
    End.

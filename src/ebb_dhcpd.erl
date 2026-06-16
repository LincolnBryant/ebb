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
    start_link/0,
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

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    {ok, Socket} = gen_udp:open(67, [{active, once}, {broadcast, true}, binary]),
    {ok, #{
        socket => Socket
    }}.

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
    Msg = ebb_dhcp_packet:decode(Packet),
    % Consume the packet and send a reply as a side effect, as necessary
    route_msg(Msg, Socket),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

route_msg(Msg = #dhcp_message{op = bootrequest, options = Options}, Socket) ->
    MsgType = proplists:get_value(message_type, Options),
    case MsgType of
        dhcpdiscover ->
            OfferLease =
                case ebb_dhcp_pool_mem:get_offer(Msg) of
                    false ->
                        ebb_dhcp_pool_mem:create_offer(Msg);
                    Existing ->
                        Existing
                end,
            send_offer(Msg, OfferLease, Socket);
        dhcprequest ->
            ok;
        % TODO:
        %ebb_dhcp_pool_mem:accept_offer(Msg, Socket);
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
        hlen = HLen
    } = DiscoverMsg,
    % Pull the client IP out of the offer
    #dhcp_lease{
        ip = ClientIP,
        subnet_mask = SubnetMask,
        duration = Duration
    } = Offer,
    % Grab the server IP from the socket
    {ok, {ServerIP, _Port}} = inet:sockname(Socket),
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
    logger:notice("Created message: ~p", [OfferMsg]),
    OfferPacket = ebb_dhcp_packet:encode(OfferMsg),
    logger:notice("Encoded message: ~p", [OfferPacket]),
    % TODO : Remove broadcast flast, unicast directly to the MAC
    gen_udp:send(Socket, {255, 255, 255, 255}, 68, OfferPacket).

%maybe_lease(Msg, LeaseTable) ->
%    Options = Msg#dhcp_message.options,
%    MacAddr = Msg#dhcp_message.chaddr,
%    MsgType = proplists:get_value(message_type, Options),
%    case MsgType of
%        dhcpdiscover ->
%            Lease = ebb_dhcp_pool_mem:get_or_create(MacAddr),
%            {Lease, LeaseTable};
%        _ ->
%            logger:debug("Not implemented"),
%            {undefined, LeaseTable}
%    end.

%% This all needs to be redone.
%% Lease table should be a separate process and we send mesages to it.
%% We need to determine all of the terminating states for when a reply is sent
%% Thread through stuff correctly.

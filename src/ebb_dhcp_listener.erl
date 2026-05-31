-module(ebb_dhcp_listener).
-behaviour(gen_server).

%% API
-export([start_link/0]).

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

handle_info({udp, _Socket, Addr, Port, Packet}, State) ->
    case decode(Packet) of
        {ok, Msg} ->
            ebb_dhcpd:handle_request(Addr, Port, Msg);
        {error, _} ->
            ok
    end,
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions
decode(Packet) ->
    % implement moe
    {ok, Packet}.

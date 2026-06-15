-module(ebb_dhcp_table).
-behaviour(gen_server).

-include("dhcp.hrl").

%% API
-export([
		 start_link/0,
		 get_or_create/1
		]).


%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-doc """ 
Retrieve/extend an existing DHCP lease, or create a new one. Identifier is
treated as an opaque object, as clients may send:
	- UUID (Option 97)
	- Arbitrary string identifier OR MAC Address (Option 61)
	- MAC Address (ChAddr)
""".
-spec get_or_create(mac_address() | binary()) -> ok.
get_or_create(_Identifier) ->
	ok.

init([]) ->
    {ok, #{}}.

handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({expire, _ID}, State) ->
	{ok, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Internal functions

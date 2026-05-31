%%%-------------------------------------------------------------------
%% @doc ebb public API
%% @end
%%%-------------------------------------------------------------------

-module(ebb_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ebb_sup:start_link().

stop(_State) ->
    ok.

%% internal functions

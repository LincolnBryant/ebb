%%%-------------------------------------------------------------------
%% @doc ebb public API
%% @end
%%%-------------------------------------------------------------------

-module(ebb_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    case ebb_config:load() of
        ok ->
            ebb_sup:start_link();
        {error, Reason} ->
            logger:critical("Refusing to start: ~s", [Reason]),
            {error, {config_error, lists:flatten(Reason)}}
    end.

stop(_State) ->
    ok.

%% internal functions

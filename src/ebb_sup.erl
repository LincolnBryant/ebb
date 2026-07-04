-module(ebb_sup).
-moduledoc """
ebb top level supervisor. 
""".

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 3,
        period => 5
    },
    ChildSpecs = provision_specs(),
    case ChildSpecs of
        [] -> logger:warning("No features enabled, ebb is running idle");
        _ -> ok
    end,
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions

%% Provisioning, gated on the [dhcp] config section.
provision_specs() ->
    case ebb_config:enabled(dhcp) of
        true ->
            [
                #{
                    id => ebb_provision_sup,
                    start => {ebb_provision_sup, start_link, []},
                    type => supervisor
                }
            ];
        false ->
            []
    end.

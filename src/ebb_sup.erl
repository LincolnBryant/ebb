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
    % Any future subsystems can be added here, too
    ChildSpecs = dhcp_specs(),
    case ChildSpecs of
        [] -> logger:warning("No features enabled, ebb is running idle");
        _ -> ok
    end,
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions

%% Provisioning, gated on the [dhcp] config section.
dhcp_specs() ->
    case ebb_config:enabled(dhcp) of
        true ->
            Subnets = ebb_config:get([dhcp, subnet]),
            [
                #{
                    id => ebb_dhcp_sup,
                    start => {ebb_dhcp_sup, start_link, [Subnets]},
                    type => supervisor
                }
            ];
        false ->
            []
    end.

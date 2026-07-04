-module(ebb_provision_sup).
-moduledoc """
Supervisor for the provisioning feature, including:
  - the DHCP listener and its lease pool. 

Started by `ebb_sup` only when the `[dhcp]` section is present in the
configuration.
""".

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 3,
        period => 5
    },
    ChildSpecs = [
        #{
            id => ebb_dhcp_pool_mem,
            start => {ebb_dhcp_pool_mem, start_link, []}
        },
        #{
            id => ebb_dhcpd,
            start => {ebb_dhcpd, start_link, []}
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

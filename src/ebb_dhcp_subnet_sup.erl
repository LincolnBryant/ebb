-module(ebb_dhcp_subnet_sup).
-moduledoc """
Supervisor process for DHCP subnets

Started by `ebb_sup` only when the `[dhcp]` section is present in the
configuration and a [[dhcp.subnet]] is defined.

Starts a dhcpd that will own the sockets and pool processes that own the pool ranges.
""".

-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

-include("dhcp.hrl").

start_link(SubnetMap) ->
    supervisor:start_link(?MODULE, [SubnetMap]).

init([SubnetMap]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 3,
        period => 5
    },
    logger:notice("SubnetMap: ~p", [SubnetMap]),
    ChildSpecs = pool_specs(SubnetMap),
    {ok, {SupFlags, ChildSpecs}}.

% For each subnet, start a subnet supervisor

pool_specs(#{interface := Interface, cidr := Cidr, pool := Pools}) ->
    DhcpdSpec = #{
        id => ebb_dhcpd,
        start => {ebb_dhcpd, start_link, [Interface, Cidr]}
    },
    PoolSpecFun =
        fun(#{range := Range} = Pool, Acc) ->
            Backend = maps:get(backend, Pool, ?DEFAULT_POOL_BACKEND),
            Module = list_to_existing_atom("ebb_dhcp_pool_" ++ Backend),
            Spec = #{
                id => {pool, Range},
                start => {Module, start_link, [Range]}
            },
            [Spec | Acc]
        end,
    lists:foldl(PoolSpecFun, [DhcpdSpec], Pools).

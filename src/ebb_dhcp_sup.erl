-module(ebb_dhcp_sup).
-moduledoc """
Supervisor process for DHCP subnets

Started by `ebb_sup` only when the `[dhcp]` section is present in the
configuration and a [[dhcp.subnet]] is defined.
""".

-behaviour(supervisor).

-export([start_link/1]).
-export([init/1]).

start_link(Subnets) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, [Subnets]).

init([Subnets]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 3,
        period => 5
    },
    ChildSpecs = subnet_specs(Subnets),
    {ok, {SupFlags, ChildSpecs}}.

% For each subnet, start a subnet supervisor
subnet_specs(Subnets) ->
    [
        #{
            id => {subnet_sup, Cidr},
            start => {ebb_dhcp_subnet_sup, start_link, [SubnetMap]}
        }
     || #{cidr := Cidr} = SubnetMap <- Subnets
    ].

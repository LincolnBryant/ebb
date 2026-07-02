%%%-------------------------------------------------------------------
%% @doc ebb top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(ebb_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional
init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 3,
        period => 5
    },
    ChildSpecs = [
        #{
            id => ebb_dhcp_pool_mem,
            start => {ebb_dhcp_pool_mem, start_link, []},
            type => worker
        },
        #{
            id => ebb_dhcpd,
            start => {ebb_dhcpd, start_link, []},
            type => worker
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.

%% internal functions

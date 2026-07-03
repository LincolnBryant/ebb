-module(ebb_config).
-moduledoc """
Configuration for ebb, loaded from a TOML file into persistent terms. A
configuration file is required to boot ebb. The file is resolved in this order:

1. The path in the `EBB_CONFIG` environment variable
2. `./ebb.toml`
3. `/etc/ebb/ebb.toml`
""".

-export([load/0, get/1, enabled/1]).
%% Exported for tests
-export([load_file/1]).

-define(PT_KEY, ?MODULE).
-define(LOCAL_PATH, "ebb.toml").
-define(SYSTEM_PATH, "/etc/ebb/ebb.toml").

%%--------------------------------------------------------------------
%% API
%%--------------------------------------------------------------------

-doc """
Returns an error if no file can be found, the file is unreadable or
unparseable, or any required key is missing.
""".
-spec load() -> ok | {error, io_lib:chars()}.
load() ->
    case resolve_path() of
        {path, Path} ->
            load_file(Path);
        {error, Reason} ->
            {error, Reason}
    end.

-doc """
Load configuration from an explicit path. See also `load/0`.
""".
-spec load_file(file:name_all()) -> ok | {error, io_lib:chars()}.
load_file(Path) ->
    case tomerl:read_file(Path) of
        {ok, Raw} ->
            try
                store(Path, atomize(Raw))
            catch
                throw:{unknown_key, Key} ->
                    {error,
                        io_lib:format("unknown configuration key \"~s\" in ~s", [
                            Key, Path
                        ])}
            end;
        {error, Reason} ->
            {error, io_lib:format("cannot read ~s: ~p", [Path, Reason])}
    end.

store(Path, Config) ->
    case missing_keys(Config) of
        [] ->
            persistent_term:put(?PT_KEY, Config),
            logger:notice("Loaded configuration from ~s, enabled features: ~p", [
                Path, [F || F <- maps:keys(features()), is_map_key(F, Config)]
            ]),
            ok;
        Missing ->
            {error,
                io_lib:format("~s is missing required keys: ~s", [
                    Path, string:join(Missing, ", ")
                ])}
    end.

-doc """
Fetch a configuration value by path, e.g. `get([dhcp, listen_port])`.
Crashes on unknown paths; see `features/0`.
""".
-spec get([atom()]) -> term().
get(Path) when is_list(Path) ->
    lists:foldl(fun maps:get/2, persistent_term:get(?PT_KEY), Path).

-doc """
Features are gated by presence: a feature is enabled iff its section
exists in the configuration file.
""".
-spec enabled(atom()) -> boolean().
enabled(Feature) ->
    is_map_key(Feature, persistent_term:get(?PT_KEY)).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

%% Known feature sections and the keys each requires when present.
%% An absent section simply disables the feature.
features() ->
    #{
        dhcp => [listen_port, range, lease_seconds, offer_timeout_seconds]
    }.

missing_keys(Config) ->
    maps:fold(
        fun(Feature, RequiredKeys, Acc) ->
            case Config of
                #{Feature := Section} ->
                    Acc ++
                        [
                            atom_to_list(Feature) ++ "." ++ atom_to_list(Key)
                         || Key <- RequiredKeys, not is_map_key(Key, Section)
                        ];
                #{} ->
                    Acc
            end
        end,
        [],
        features()
    ).

resolve_path() ->
    case os:getenv("EBB_CONFIG") of
        false -> search_default_paths();
        "" -> search_default_paths();
        Path -> explicit_path(Path)
    end.

search_default_paths() ->
    case lists:search(fun filelib:is_regular/1, [?LOCAL_PATH, ?SYSTEM_PATH]) of
        {value, Path} ->
            {path, Path};
        false ->
            {error,
                io_lib:format(
                    "no configuration file found; provide ~s, ~s,"
                    " or set EBB_CONFIG",
                    [?LOCAL_PATH, ?SYSTEM_PATH]
                )}
    end.

explicit_path(Path) ->
    case filelib:is_regular(Path) of
        true ->
            {path, Path};
        false ->
            {error,
                io_lib:format(
                    "EBB_CONFIG points at ~s, which does not exist"
                    " or is not a regular file",
                    [Path]
                )}
    end.

%% tomerl produces binary keys; convert them (and table arrays) to the
%% atom-keyed shape used internally.
atomize(Map) when is_map(Map) ->
    maps:fold(
        fun(K, V, Acc) -> Acc#{binary_to_existing_atom(K) => atomize(V)} end,
        #{},
        Map
    );
atomize(List) when is_list(List) ->
    [atomize(V) || V <- List];
atomize(Value) ->
    Value.

-module(ebb_config).
-moduledoc """
Configuration for ebb, loaded from a TOML file into persistent terms. A
configuration file is required to boot ebb. The file is resolved in this order:

1. The path in the `EBB_CONFIG` environment variable
2. `./ebb.toml`
3. `/etc/ebb/ebb.toml`
""".

-export([load/0, get/1, enabled/1]).

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
    maybe
        {path, File} ?= resolve_path(),
        logger:notice("Reading configuration from ~p", File),
        {ok, Config} ?= read_toml(File),
        logger:notice("Parsed configuration as valid TOML"),
        ok ?= ebb_config_validator:check_structure(Config),
        logger:notice("Validated configuration structure"),
        persistent_term:put(?MODULE, atomize(Config))
    else
        {error, Reason} ->
            {error, Reason}
    end.

-doc """
Fetch a configuration value by path, e.g. `get([dhcp, listen_port])`.
""".
-spec get([atom()]) -> term().
get(Path) when is_list(Path) ->
    lists:foldl(fun maps:get/2, persistent_term:get(?MODULE), Path).

-doc """
Features are gated by presence: a feature is enabled iff its section
exists in the configuration file.
""".
-spec enabled(atom()) -> boolean().
enabled(Feature) ->
    is_map_key(Feature, persistent_term:get(?MODULE)).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

resolve_path() ->
    case os:getenv("EBB_CONFIG") of
        false -> search_default_paths();
        "" -> search_default_paths();
        Path -> explicit_path(Path)
    end.

read_toml(File) ->
    case tomerl:read_file(File) of
        {ok, Raw} ->
            {ok, Raw};
        {error, Reason} ->
            {error, io_lib:format("cannot read ~s: ~p", [File, Reason])}
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
atomize(Value) when is_binary(Value) ->
    binary_to_list(Value);
atomize(Value) ->
    Value.

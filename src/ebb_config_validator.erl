-module(ebb_config_validator).
-moduledoc """
ebb configuration validator. ensures that configuration contains only valid
keys
""".
-export([schema/0, check_structure/1, format_errors/1]).

-include("dhcp.hrl").

%% Keys only; values pass through unexamined. Schema nodes:
%%   #{...}          table; validated if present, absent stays absent
%%   {array, #{...}} array of tables; each element validated
%%   required        leaf that must be present
%%   optional        leaf that may be absent
%%   {default, V}    leaf that gets V when absent
%%
%% Input keys not in the schema are errors.
schema() ->
    #{
        dhcp => #{
            subnet =>
                {array, #{
                    cidr => required,
                    interface => required,
                    next_server => optional,
                    boot_file => optional,
                    option => #{
                        routers => optional,
                        domain_name_servers => optional
                    },
                    pool =>
                        {array, #{
                            range => required,
                            lease_seconds => {default, ?DEFAULT_LEASE_SECONDS},
                            min_lease_seconds => {default, ?DEFAULT_MIN_LEASE_SECONDS},
                            max_lease_seconds => {default, ?DEFAULT_MAX_LEASE_SECONDS},
                            offer_timeout_seconds =>
                                {default, ?DEFAULT_OFFER_TIMEOUT_SECONDS},
                            backend => #{
                                type => {default, ?DEFAULT_POOL_BACKEND},
                                path => optional
                            }
                        }}
                }},
            proxy =>
                {array, #{
                    interface => required,
                    next_server => required,
                    boot_file => required
                }}
        }
    }.

-doc """
Structural pass: check the parsed TOML against `schema/0`. Keys only;
values pass through unexamined.
""".
-spec check_structure(map()) ->
    ok | {error, [{Path :: [term()], Reason :: atom()}]}.
check_structure(Config) ->
    case walk(schema(), Config, [], []) of
        [] -> ok;
        Errors -> {error, lists:reverse(Errors)}
    end.

-doc """
Render the error list of `validate/1` as one line per error, e.g.
`dhcp.subnet[1].pool[2].optiion: unknown key`.
""".
-spec format_errors([{[term()], atom()}]) -> io_lib:chars().
format_errors(Errors) ->
    lists:join($\n, [format_error(E) || E <- Errors]).

%%--------------------------------------------------------------------
%% Internal
%%--------------------------------------------------------------------

%% walk(SchemaNode, Input, PathRev, Errors) -> Errors
%%
%% SchemaNode and Input descend the schema and the parsed TOML in
%% lockstep. PathRev is the current position, innermost first. Errors
%% accumulate; the walk never aborts.

%% Table: sweep input for unknown keys and recurse into known ones,
%% then sweep the schema for missing required keys.
walk(Node, Input, PathRev, Errors) when is_map(Node), is_map(Input) ->
    ByBin = #{atom_to_binary(A) => S || A := S <- Node},
    Errors1 = maps:fold(
        fun(K, V, Acc) ->
            case ByBin of
                #{K := SubNode} -> walk(SubNode, V, [K | PathRev], Acc);
                #{} -> err(unknown_key, [K | PathRev], Acc)
            end
        end,
        Errors,
        Input
    ),
    maps:fold(
        fun
            (A, required, Acc) ->
                case is_map_key(atom_to_binary(A), Input) of
                    true -> Acc;
                    false -> err(missing_key, [A | PathRev], Acc)
                end;
            (_A, _SubNode, Acc) ->
                Acc
        end,
        Errors1,
        Node
    );
walk(Node, _Input, PathRev, Errors) when is_map(Node) ->
    err(expected_table, PathRev, Errors);
%% Array of tables: recurse per element, 1-based index in the path.
walk({array, ElemNode}, Input, PathRev, Errors) when is_list(Input) ->
    {_, Errors1} = lists:foldl(
        fun(Elem, {I, Acc}) ->
            {I + 1, walk(ElemNode, Elem, [I | PathRev], Acc)}
        end,
        {1, Errors},
        Input
    ),
    Errors1;
walk({array, _ElemNode}, _Input, PathRev, Errors) ->
    err(expected_array, PathRev, Errors);
%% Leaves: the key exists in the schema, which is all we check.
walk(required, _V, _PathRev, Errors) ->
    Errors;
walk(optional, _V, _PathRev, Errors) ->
    Errors;
walk({default, _}, _V, _PathRev, Errors) ->
    Errors.

err(Reason, PathRev, Errors) ->
    [{lists:reverse(PathRev), Reason} | Errors].

format_error({Path, Reason}) ->
    io_lib:format("~s: ~s", [format_path(Path), format_reason(Reason)]).

format_reason(unknown_key) -> "unknown key";
format_reason(missing_key) -> "missing required key";
format_reason(expected_table) -> "expected a table";
format_reason(expected_array) -> "expected an array of tables ([[...]])".

%% [dhcp, subnet, 1, pool, 2, range] -> "dhcp.subnet[1].pool[2].range"
format_path([First | Rest]) ->
    [segment(First) | [dotted(S) || S <- Rest]].

dotted(I) when is_integer(I) -> io_lib:format("[~b]", [I]);
dotted(S) -> [$. | segment(S)].

segment(A) when is_atom(A) -> atom_to_list(A);
segment(B) when is_binary(B) -> binary_to_list(B).

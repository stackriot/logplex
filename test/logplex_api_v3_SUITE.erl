-module(logplex_api_v3_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-compile(export_all).

all() ->
    [{group, channels}
     , {group, drains}
    ].

groups() ->
    [{channels,
      [channel_service_unavailable
       , channel_method_not_allowed
       , create_channel_without_tokens
       , create_channel_with_tokens
       , update_channel_with_tokens
       , update_channel_and_remove_some_tokens
       , update_channel_and_nuke_tokens
       , get_channel_without_tokens
       , get_channel_with_tokens
       , delete_channel
       , reject_invalid_channel_payload
      ]},
     {drains,
      [reserve_drain_without_drainurl
       , reserve_drain_with_drainurl
       , update_drain_url
       , update_invalid_drain_url
       , get_channel_with_drain
       , cannot_add_duplicate_drain
       , cannot_add_more_drains
       , cannot_update_non_existing_drain
      ]}
    ].

init_per_suite(Config) ->
    set_os_vars(),
    ok = logplex_app:a_start(logplex, temporary),
    [{api_v3_url, logplex_app:config(http_v3_url)}
     , {auth, "Basic " ++ logplex_app:config(auth_key)}
     | Config].

end_per_suite(Config) ->
    application:stop(logplex),
    Config.

init_per_testcase(channel_service_unavailable, Config) ->
    logplex_app:set_config(api_status, disabled),
    Config;
init_per_testcase(cannot_add_more_drains, Config) ->
    OldLimit = logplex_app:config(max_drains_per_channel),
    logplex_app:set_config(max_drains_per_channel, 1),
    [{old_max_drains_per_channel, OldLimit}
     | Config];
init_per_testcase(_, Config) ->
    Config.

end_per_testcase(channel_service_unavailable, Config) ->
    logplex_app:set_config(api_status, normal),
    Config;
end_per_testcase(cannot_add_more_drains, Config) ->
    OldLimit = ?config(old_max_drains_per_channel, Config),
    logplex_app:set_config(max_drains_per_channel, OldLimit),
    Config;
end_per_testcase(_, Config) ->
    Config.

channel_service_unavailable(Config) ->
    Channel = new_channel(),
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel,
    Props = logplex_api_SUITE:request(get, Url, []),
    ?assertEqual(503, proplists:get_value(status_code, Props)),
    ?assertEqual("Service Unavailable", proplists:get_value(http_reason, Props)),
    Config.

channel_method_not_allowed(Config) ->
    Channel = new_channel(),
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel,
    [begin
         Props = logplex_api_SUITE:request(Method, Url, []),
         ?assertEqual(405, proplists:get_value(status_code, Props)),
         ?assertEqual("Method Not Allowed", proplists:get_value(http_reason, Props))
     end || Method <- [post, head, options]],
    Config.

create_channel_without_tokens(Config) ->
    Channel = new_channel(),
    Props = put_channel(Channel, [], Config),
    ct:pal("put channel resp: ~p~n", [Props]),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertEqual(201, proplists:get_value(status_code, Props)),
    ?assertEqual("Created", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    [{channel, Channel} | Config].

create_channel_with_tokens(Config) ->
    Channel = new_channel(),
    Tokens = [new_token_name() || _ <- lists:seq(1,5)],
    Props = put_channel(Channel, Tokens, Config),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ReceivedTokens = maps:to_list(maps:get(<<"tokens">>, Resp)),
    ?assertEqual(length(Tokens), length(ReceivedTokens)),
    ?assert(lists:all(fun(Token) -> lists:member(Token, Tokens) end,
                      [binary_to_list(Token) || {Token, _} <- ReceivedTokens])),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertEqual(201, proplists:get_value(status_code, Props)),
    ?assertEqual("Created", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    [{channel, Channel}
     , {tokens, Tokens}
     | Config].


update_channel_with_tokens(Config0) ->
    Config = create_channel_without_tokens(Config0),
    Channel = ?config(channel, Config),
    Tokens = [new_token_name() || _ <- lists:seq(1,5)],
    Props = put_channel(Channel, Tokens, Config),
    ct:pal("put channel resp: ~p~n", [Props]),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ReceivedTokens = maps:to_list(maps:get(<<"tokens">>, Resp)),
    ?assertEqual(length(Tokens), length(ReceivedTokens)),
    ?assert(lists:all(fun(Token) -> lists:member(Token, Tokens) end,
                      [binary_to_list(Token) || {Token, _} <- ReceivedTokens])),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertEqual(200, proplists:get_value(status_code, Props)),
    ?assertEqual("OK", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    [{tokens, Tokens} | Config].

update_channel_and_remove_some_tokens(Config0) ->
    Config = create_channel_with_tokens(Config0),
    Channel = ?config(channel, Config),
    Tokens = lists:nthtail(2, ?config(tokens, Config)),
    Props = put_channel(Channel, Tokens, Config),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ReceivedTokens = maps:to_list(maps:get(<<"tokens">>, Resp)),
    ?assertEqual(length(Tokens), length(ReceivedTokens)),
    ?assert(lists:all(fun(Token) -> lists:member(Token, Tokens) end,
                      [binary_to_list(Token) || {Token, _} <- ReceivedTokens])),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertEqual(200, proplists:get_value(status_code, Props)),
    ?assertEqual("OK", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    [{tokens, Tokens} | Config].

update_channel_and_nuke_tokens(Config0) ->
    Config = create_channel_with_tokens(Config0),
    Channel = ?config(channel, Config),
    Props = put_channel(Channel, [], Config),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertEqual(200, proplists:get_value(status_code, Props)),
    ?assertEqual("OK", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    ?assert(not maps:is_key(<<"tokens">>, Resp)),
    Config.

get_channel_without_tokens(Config0) ->
    Config = create_channel_without_tokens(Config0),
    Channel = ?config(channel, Config),
    Props = get_channel(Channel, Config),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertEqual(200, proplists:get_value(status_code, Props)),
    ?assertEqual("OK", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    Config.

get_channel_with_tokens(Config0) ->
    Config = create_channel_with_tokens(Config0),
    Channel = ?config(channel, Config),
    Tokens = ?config(tokens, Config),
    Props = get_channel(Channel, Config),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ReceivedTokens = maps:to_list(maps:get(<<"tokens">>, Resp)),
    ?assertEqual(length(Tokens), length(ReceivedTokens)),
    ?assert(lists:all(fun(Token) -> lists:member(Token, Tokens) end,
                      [binary_to_list(Token) || {Token, _} <- ReceivedTokens])),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertEqual(200, proplists:get_value(status_code, Props)),
    ?assertEqual("OK", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    Config.

delete_channel(Config0) ->
    Config = create_channel_without_tokens(Config0),
    Channel = ?config(channel, Config),
    Props = delete_channel(Channel, Config),
    ct:pal("delete channel resp: ~p~n", [Props]),
    ?assertEqual(204, proplists:get_value(status_code, Props)),
    ?assertEqual("No Content", proplists:get_value(http_reason, Props)).

reject_invalid_channel_payload(Config) ->
    Channel = new_channel(),
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel,
    Headers = [{"Authorization", ?config(auth, Config)}],
    JSON = jsx:encode([<<"asdf">>, 123, [<<"test">>]]),
    Opts = [{headers, Headers}, {body, JSON}, {timeout, timer:seconds(10)}],
    Props = logplex_api_SUITE:put_(Url, Opts),
    Body = proplists:get_value(body, Props),
    RespHeaders = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ?assertEqual(<<"invalid payload">>, maps:get(<<"error">>, Resp)),
    ?assertEqual(400, proplists:get_value(status_code, Props)),
    ?assertEqual("Bad Request", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", RespHeaders)),
    ?assert(is_list(proplists:get_value("request-id", RespHeaders))),
    Config.

reserve_drain_without_drainurl(Config0) ->
    Config = create_channel_without_tokens(Config0),
    Channel = ?config(channel, Config),
    Props = create_drain(Channel, undefined, Config),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    DrainId = maps:get(<<"id">>, Resp),
    DrainToken = maps:get(<<"token">>, Resp),
    ?assert(is_integer(DrainId)),
    ?assert(is_binary(DrainToken)),
    ?assert(not maps:is_key(<<"url">>, Resp)),
    ?assertEqual(201, proplists:get_value(status_code, Props)),
    ?assertEqual("Created", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    ?assert(is_list(proplists:get_value("location", Headers))),
    [{drain, {DrainId, DrainToken, undefined}}
     | Config].

reserve_drain_with_drainurl(Config0) ->
    Config = create_channel_without_tokens(Config0),
    Channel = ?config(channel, Config),
    DrainUrl = new_drain_url(),
    Props = create_drain(Channel, DrainUrl, Config),
    Body = proplists:get_value(body, Props),
    Headers = proplists:get_value(headers, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    DrainId = maps:get(<<"id">>, Resp),
    DrainToken = maps:get(<<"token">>, Resp),
    ?assert(is_integer(DrainId)),
    ?assert(is_binary(DrainToken)),
    ?assertEqual(DrainUrl, maps:get(<<"url">>, Resp)),
    ?assertEqual(201, proplists:get_value(status_code, Props)),
    ?assertEqual("Created", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    ?assert(is_list(proplists:get_value("location", Headers))),
    [{drain, {DrainId, DrainToken, DrainUrl}}
     | Config].

update_drain_url(Config0) ->
    Config = reserve_drain_without_drainurl(Config0),
    Channel = ?config(channel, Config),
    {DrainId, DrainToken, _} = proplists:get_value(drain, Config),
    DrainUrl = new_drain_url(),
    Props = update_drain(Channel, DrainId, DrainUrl, Config),
    ct:pal("~p~n", [Props]),
    Headers = proplists:get_value(headers, Props),
    Body = proplists:get_value(body, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ?assertEqual(DrainId, maps:get(<<"id">>, Resp)),
    ?assertEqual(DrainToken, maps:get(<<"token">>, Resp)),
    ?assertEqual(DrainUrl, maps:get(<<"url">>, Resp)),
    ?assertEqual(200, proplists:get_value(status_code, Props)),
    ?assertEqual("OK", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    ?assert(not proplists:is_defined("location", Headers)),
    [{drain, {DrainId, DrainToken, DrainUrl}}
     | Config].

update_invalid_drain_url(Config0) ->
    Config = reserve_drain_without_drainurl(Config0),
    Channel = ?config(channel, Config),
    {DrainId, _, _} = proplists:get_value(drain, Config),
    DrainUrl = <<"i am not a url">>,
    Props = update_drain(Channel, DrainId, DrainUrl, Config),
    ?assertEqual(400, proplists:get_value(status_code, Props)),
    ?assertEqual("Bad Request", proplists:get_value(http_reason, Props)),
    Config.

get_channel_with_drain(Config0) ->
    Config = reserve_drain_with_drainurl(Config0),
    Channel = ?config(channel, Config),
    {DrainId, DrainToken, DrainUrl} = proplists:get_value(drain, Config),
    Props = get_channel(Channel, Config),
    ct:pal("~p~n", [Props]),
    Headers = proplists:get_value(headers, Props),
    Body = proplists:get_value(body, Props),
    Resp = jsx:decode(list_to_binary(Body), [return_maps]),
    ?assertMatch(Channel, binary_to_list(maps:get(<<"channel">>, Resp))),
    ?assertMatch([#{<<"id">> := DrainId, <<"token">> := DrainToken, <<"url">> := DrainUrl}],
                 maps:get(<<"drains">>, Resp)),
    ?assertEqual(200, proplists:get_value(status_code, Props)),
    ?assertEqual("OK", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    Config.

cannot_add_duplicate_drain(Config0) ->
    Config = reserve_drain_with_drainurl(Config0),
    Channel = ?config(channel, Config),
    {_, _, DrainUrl} = proplists:get_value(drain, Config),
    Props = create_drain(Channel, DrainUrl, Config),
    Headers = proplists:get_value(headers, Props),
    ct:pal("~p~n", [Props]),
    ?assertEqual(409, proplists:get_value(status_code, Props)),
    ?assertEqual("Conflict", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    Config.

cannot_add_more_drains(Config0) ->
    Config = reserve_drain_with_drainurl(Config0),
    Channel = ?config(channel, Config),
    DrainUrl = new_drain_url(),
    Props = create_drain(Channel, DrainUrl, Config),
    Headers = proplists:get_value(headers, Props),
    ?assertEqual(422, proplists:get_value(status_code, Props)),
    ?assertEqual("Unprocessable Entity", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    Config.

cannot_update_non_existing_drain(Config0) ->
    Config = create_channel_without_tokens(Config0),
    Channel = ?config(channel, Config),
    DrainUrl = new_drain_url(),
    FakeDrainId = 123123123123123123123123,
    Props = update_drain(Channel, FakeDrainId, DrainUrl, Config),
    Headers = proplists:get_value(headers, Props),
    ?assertEqual(404, proplists:get_value(status_code, Props)),
    ?assertEqual("Not Found", proplists:get_value(http_reason, Props)),
    ?assertEqual("application/json", proplists:get_value("content-type", Headers)),
    ?assert(is_list(proplists:get_value("request-id", Headers))),
    Config.

put_channel(Channel, Tokens, Config) ->
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel,
    Headers = [{"Authorization", ?config(auth, Config)}],
    TokenList = [list_to_binary(Token) || Token <- Tokens],
    JSON = jsx:encode(maps:from_list([{<<"tokens">>, TokenList} || length(TokenList) > 0])),
    Opts = [{headers, Headers}, {body, JSON}, {timeout, timer:seconds(10)}],
    logplex_api_SUITE:put_(Url, Opts).

get_channel(Channel, Config) ->
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel,
    Headers = [{"Authorization", ?config(auth, Config)}],
    Opts = [{headers, Headers}, {timeout, timer:seconds(10)}],
    logplex_api_SUITE:get_(Url, Opts).

delete_channel(Channel, Config) ->
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel,
    Headers = [{"Authorization", ?config(auth, Config)}],
    Opts = [{headers, Headers}, {timeout, timer:seconds(10)}],
    logplex_api_SUITE:request(delete, Url, Opts).

create_drain(Channel, DrainUrl, Config) ->
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel ++ "/drains",
    Headers = [{"Authorization", ?config(auth, Config)}],
    JSON = jsx:encode(maps:from_list([{<<"url">>, DrainUrl} || DrainUrl =/= undefined])),
    Opts = [{headers, Headers}, {body, JSON}, {http_opts, [{autoredirect, false}]},
            {timeout, timer:seconds(10)}],
    logplex_api_SUITE:post(Url, Opts).

update_drain(Channel, DrainId, DrainUrl, Config) ->
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel ++ "/drains/" ++ integer_to_list(DrainId),
    Headers = [{"Authorization", ?config(auth, Config)}],
    JSON = jsx:encode(maps:from_list([{<<"url">>, DrainUrl} || DrainUrl =/= undefined])),
    Opts = [{headers, Headers}, {body, JSON}, {timeout, timer:seconds(10)}],
    logplex_api_SUITE:put_(Url, Opts).

delete_drain(Channel, DrainId, Config) ->
    Url = ?config(api_v3_url, Config) ++ "/v3/channels/" ++ Channel ++ "/drains/" ++ integer_to_list(DrainId),
    Headers = [{"Authorization", ?config(auth, Config)}],
    Opts = [{headers, Headers}, {timeout, timer:seconds(10)}],
    logplex_api_SUITE:request(delete, Url, Opts).

new_channel() ->
    "app-" ++ uuid:to_string(uuid:v4()).

new_token_name() ->
    "token-" ++ uuid:to_string(uuid:v4()).

new_drain_url() ->
    list_to_binary([<<"http://my.drain.com/">>, uuid:to_binary(uuid:v4())]).

set_os_vars() ->
    [os:putenv(Key,Val) || {Key,Val} <-
        [{"INSTANCE_NAME", net_adm:localhost()},
         {"LOCAL_IP", "localhost"},
         {"CLOUD_DOMAIN", "localhost"},
         {"LOGPLEX_AUTH_KEY", uuid:to_string(uuid:v4())},
         {"LOGPLEX_COOKIE", "ct test"},
         {"LOGPLEX_NODE_NAME", atom_to_list(node())},
         {"LOGPLEX_API_ENDPOINT_URL", "http://localhost:8001"}
        ]].

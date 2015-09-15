-module(logplex_tls_syslog_drain_SUITE).
-include_lib("common_test/include/ct.hrl").
-include_lib("ex_uri/include/ex_uri.hrl").
-include("../src/logplex_tlssyslog_drain.hrl").
-compile(export_all).

-include("logplex_test_helpers.hrl").

all() -> [ensure_drain_endpoint, close_if_idle, close_if_old].

init_per_suite(Config0) ->
  set_os_vars(),
  ok = logplex_app:a_start(logplex, temporary),
  CertsPath = filename:join([code:lib_dir(ssl), "examples", "certs", "etc", "server"]),
  [{certs_path, CertsPath} | Config0].

end_per_suite(_Config) ->
  application:stop(logplex),
  meck:unload().

init_per_testcase(_TestCase, Config0) ->
  IdleTimeout = 50,
  IdleFuzz = 1,
  application:set_env(logplex, tcp_syslog_idle_timeout, IdleTimeout),
  application:set_env(logplex, tcp_syslog_idle_fuzz, IdleFuzz),
  Config1 = init_drain_endpoint(Config0),
  init_logplex_drain(Config1).

end_per_testcase(_TestCase, Config) ->
  end_drain_endpoint(),
  end_logplex_drain(Config),
  ok.

wait_for_drain_error(Error) ->
  {ok, Error} = wait_for_drain_(drain_error).

wait_for_log() ->
  wait_for_drain_(drain_data).

wait_for_drain_(Prefix) ->
  receive
    {Prefix, State} -> {ok, State};
    Other -> ct:fail("Unexpected message expected=~p got=~p", [{Prefix, '_'}, Other])
  after
    5000 ->
      {error, {no_logs_after, 5000}}
  end.

init_drain_endpoint(Config0) ->
  _CertsPath = ?config(certs_path, Config0),
  Port = 9601,
  {ok, _} = ranch:start_listener(drain_endpoint, 1,
                                 ranch_tcp, [{port, Port}],
                                 drain_test_protocol, [{send_to, self()}]),
  [{drain_uri, "syslog://127.0.0.1:" ++ integer_to_list(Port) ++ "/"} | Config0].

end_drain_endpoint() ->
  ranch:stop_listener(drain_endpoint).

init_logplex_drain(Config0) ->
  ChannelID = 1337,
  DrainID = 31337,
  DrainTok = "d.12930-321-312213-12321",
  {ok, URI, _} = ex_uri:decode(?config(drain_uri, Config0)),
  {ok, Pid} = logplex_tcpsyslog_drain:start_link(ChannelID, DrainID, DrainTok, URI),
  unlink(Pid),
  [{channel_id, ChannelID},
   {drain_id, DrainID},
   {drain_tok, DrainTok},
   {drain_pid, Pid} | Config0].

end_logplex_drain(Config0) ->
  Drain = ?config(drain_pid, Config0),
  erlang:monitor(process, Drain),
  Drain ! shutdown,
  receive
    {'DOWN', _, _, Drain, {shutdown,call}} -> ok;
    {'DOWN', _, _, Drain, Other} -> ct:pal("DRAIN DIED OF REASON: ~p",[Other])
  after 2000 ->
          case Drain of
            undefined -> ok;
            _ -> error({not_dead, sys:get_status(Drain)})
          end
  end.

ensure_drain_endpoint(Config) ->
  URI = ?config(drain_uri, Config),
  {ok, Socket, Transport} = connect_to_endpoint(ex_uri:decode(URI)),
  ok = Transport:send(Socket, <<"ping\n">>),
  {ok, <<"ping\n">>} = wait_for_log(),
  ok.

connect_to_endpoint({ok, #ex_uri{scheme="syslog", authority=#ex_uri_authority{host=Host, port=Port}}, _Rest}) ->
  connect_to_endpoint(ranch_tcp, Host, Port, []).

connect_to_endpoint(Transport, Host, Port, Opts) ->
  {ok, Socket} = Transport:connect(Host, Port, Opts),
  {ok, Socket, Transport}.

close_if_idle(Config) ->
  ChannelID = ?config(channel_id, Config),
  IdleTimeout = logplex_app:config(tcp_syslog_idle_timeout),
  IdleFuzz = logplex_app:config(tcp_syslog_idle_fuzz),

  % triggers the drain to connect
  logplex_channel:post_msg({channel, ChannelID}, fake_msg("mymsg1")),
  {ok, _Log} = wait_for_log(),

  % triggers idle timeout on next log line
  timer:sleep(IdleFuzz + IdleTimeout + 10),

  logplex_channel:post_msg({channel, ChannelID}, fake_msg("mymsg2")),
  wait_for_drain_error(closed),
  ok.

close_if_old(_Config) ->
  ct:fail("unimplemented").

% ----------------
% Helper Functions
% ----------------

fake_msg(M) ->
    {user, debug, logplex_syslog_utils:datetime(now), "fakehost", "erlang", M}.

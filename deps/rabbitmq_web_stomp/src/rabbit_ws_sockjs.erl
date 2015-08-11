%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2012-2014 GoPivotal, Inc.  All rights reserved.
%%

-module(rabbit_ws_sockjs).

-export([init/0]).

-include_lib("rabbitmq_stomp/include/rabbit_stomp.hrl").


%% --------------------------------------------------------------------------

-spec init() -> ok.
init() ->
    Port = get_env(port, 55674),
    SockjsOpts = get_env(sockjs_opts, []) ++ [{logger, fun logger/3}],

    SockjsState = sockjs_handler:init_state(
                    <<"/stomp">>, fun service_stomp/3, {}, SockjsOpts),
    VhostRoutes = [
        {"/stomp/[...]", sockjs_cowboy_handler, SockjsState},
        {"/ws", rabbit_ws_handler, undefined}
    ],
    Routes = cowboy_router:compile([{'_',  VhostRoutes}]), % any vhost
    NbAcceptors = get_env(nb_acceptors, 100),
    cowboy:start_http(http, NbAcceptors,
                      [{port,     Port}],
                      [{env, [{dispatch, Routes}]}]),
    rabbit_log:info("rabbit_web_stomp: listening for HTTP connections on ~s:~w~n",
                    ["0.0.0.0", Port]),
    case get_env(ssl_config, []) of
        [] ->
            ok;
        Conf ->
            rabbit_networking:ensure_ssl(),
            TLSPort = proplists:get_value(port, Conf),
            cowboy:start_https(https, NbAcceptors,
                               Conf,
                               [{env, [{dispatch, Routes}]}]),
            rabbit_log:info("rabbit_web_stomp: listening for HTTPS connections on ~s:~w~n",
                            ["0.0.0.0", TLSPort])
    end,
    ok.

get_env(Key, Default) ->
    case application:get_env(rabbitmq_web_stomp, Key) of
        undefined -> Default;
        {ok, V}   -> V
    end.


%% Don't print sockjs logs
logger(_Service, Req, _Type) ->
    Req.

%% --------------------------------------------------------------------------

service_stomp(Conn, init, _State) ->
    {ok, _Sup, Pid} = rabbit_ws_sup:start_client({Conn}),
    {ok, Pid};

service_stomp(_Conn, {recv, Data}, Pid) ->
    rabbit_ws_client:sockjs_msg(Pid, Data),
    {ok, Pid};

service_stomp(_Conn, closed, Pid) ->
    rabbit_ws_client:sockjs_closed(Pid),
    ok.

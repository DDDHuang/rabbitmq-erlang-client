%%   The contents of this file are subject to the Mozilla Public License
%%   Version 1.1 (the "License"); you may not use this file except in
%%   compliance with the License. You may obtain a copy of the License at
%%   http://www.mozilla.org/MPL/
%%
%%   Software distributed under the License is distributed on an "AS IS"
%%   basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%%   License for the specific language governing rights and limitations
%%   under the License.
%%
%%   The Original Code is the RabbitMQ Erlang Client.
%%
%%   The Initial Developers of the Original Code are LShift Ltd.,
%%   Cohesive Financial Technologies LLC., and Rabbit Technologies Ltd.
%%
%%   Portions created by LShift Ltd., Cohesive Financial
%%   Technologies LLC., and Rabbit Technologies Ltd. are Copyright (C)
%%   2007 LShift Ltd., Cohesive Financial Technologies LLC., and Rabbit
%%   Technologies Ltd.;
%%
%%   All Rights Reserved.
%%
%%   Contributor(s): Ben Hood <0x6e6562@gmail.com>.
%%

-module(amqp_rpc_handler).

-behaviour(gen_server).

-include_lib("rabbitmq_server/include/rabbit.hrl").
-include_lib("rabbitmq_server/include/rabbit_framing.hrl").
-include("amqp_client.hrl").

-export([init/1, terminate/2, code_change/3, handle_call/3, handle_cast/2, handle_info/2]).

%---------------------------------------------------------------------------
% gen_server callbacks
%---------------------------------------------------------------------------
init([Connection, QueueName, ServerPid]) ->                              
    Channel = lib_amqp:start_channel(Connection),
    lib_amqp:declare_queue(Channel, QueueName),
    Tag = lib_amqp:subscribe(Channel, QueueName, self()),
    State = #rpc_server_state{channel = Channel,
                              consumer_tag = Tag,
                              server_pid = ServerPid},
    {ok, State}.

handle_info(shutdown, State = #rpc_server_state{channel = Channel,
                                                 consumer_tag = Tag}) ->
    Reply = lib_amqp:unsubscribe(Channel, Tag),
    {noreply, Reply, State};

handle_info(#'basic.consume_ok'{consumer_tag = ConsumerTag}, State) ->
    {noreply, State};

handle_info(#'basic.cancel_ok'{consumer_tag = ConsumerTag}, State) ->
    {stop, normal, State};

handle_info({content, ClassId, Properties, PropertiesBin, Payload},
            State = #rpc_server_state{server_pid = ServerPid,
                                       channel = Channel}) ->
    Props = #'P_basic'{correlation_id = CorrelationId,
                       reply_to = Q} = rabbit_framing:decode_properties(ClassId, PropertiesBin),
    Response = case gen_server:call(ServerPid, Payload) of
                    {'EXIT', Reason} ->
                        term_to_binary(Reason);
                    Other ->
                        Other
               end,
    Properties = #'P_basic'{correlation_id = CorrelationId},           
    lib_amqp:publish(Channel, <<"">>, Q, Response, Properties),
    {noreply, State}.

%---------------------------------------------------------------------------
% Rest of the gen_server callbacks
%---------------------------------------------------------------------------

handle_call(Message, From, State) ->
    {noreply, State}.

handle_cast(Message, State) ->
    {noreply, State}.

terminate(Reason, State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    State.

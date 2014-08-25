-module(rcpserver).
-include_lib("eunit/include/eunit.hrl").
-behaviour(gen_server).

%API functions
-export([start_link/0, start_link/1, get_count/0, stop/0]).
%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(DEFAULT_PORT, 1090).

-record(state, {port, lsock, request_count = 0}).


%% spawns server process
start_link(Port) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [Port], []).

%% spawns server process using default port
start_link() ->
    start_link(?DEFAULT_PORT).

%% makes caller wait for the reply
get_count() ->
	gen_server:call(?SERVER, get_count).

%% doesn't wait for the reply
stop() -> 
	gen_server:cast(?SERVER, stop).

init([Port]) ->
    {ok, LSock} = gen_tcp:listen(Port, [{active, true}]),
    %% zero timeout, triggers handle_info method to be invoked
	{ok, #state{port = Port, lsock = LSock}, 0}.

handle_call(get_count, _From, State) ->
	{reply, {ok, State#state.request_count}, State}.

handle_cast(stop, State) ->
	{stop, normal, State}.

%% handling "out-of-band" messages
%% the first clause deals with incoming tcp data
handle_info({tcp, Socket, RawData}, State) ->
	do_rpc(Socket, RawData),
	RequestCount = State#state.request_count,
	{noreply, State#state{request_count = RequestCount + 1}};
%% the second clause deals with timeouts
handle_info(timeout, #state{lsock = LSock} = State) ->
	{ok, _Sock} = gen_tcp:accept(LSock),
	{noreply, State}.

terminate(_Reason, _State) ->
	ok.
 
code_change(_OldValue, State, _Extra) ->
	{ok, State}.

%% actual rpc processing
do_rpc(Socket, RawData) ->
	try 
		{M, F, A} = split_out_mfa(RawData),
		Result = apply(M, F, A),
		get_tcp:send(Socket, io_lib:fwrite("~p~n", [Result]))
	catch
		_Class:Err ->
			gen_tcp:send(Socket, io_lib:fwrite("~p~n", [Err]))
	end.

split_out_mfa(RawData) ->
	MFA = re:replace(RawData, "\r\n$", "", [{return, list}]),
    {match, [M, F, A]} =
        re:run(MFA,
               "(.*):(.*)\s*\\((.*)\s*\\)\s*.\s*$",
                   [{capture, [1,2,3], list}, ungreedy]),
    {list_to_atom(M), list_to_atom(F), args_to_terms(A)}.

args_to_terms(RawArgs) ->
	{ok, Toks, _Line} = erl_scan:string("[" ++ RawArgs ++ "]. ", 1),
	{ok, Args} = erl_parse:parse_term(Toks),
	Args.

start_test() ->
	{ok, _} = rcpserver:start_link(1055).
%% -------------------------------------------------------------------
%%
%% Copyright (c) 2007-2011 Basho Technologies, Inc.  All Rights Reserved.
%%
%% -------------------------------------------------------------------

-module(riak_moss_wm_utils).

-export([service_available/2,
         parse_auth_header/2,
         ensure_doc/1,
         iso_8601_datetime/0,
         to_iso_8601/1,
         streaming_get/1,
         user_record_to_proplist/1]).

-include("riak_moss.hrl").
-include_lib("webmachine/include/webmachine.hrl").

%% ===================================================================
%% Public API
%% ===================================================================

service_available(RD, Ctx) ->
    %% TODO:
    %% At some point in the future
    %% this needs to check if we have
    %% an alive Riak server. Although
    %% maybe it makes more sense to be
    %% optimistic and wait untl we actually
    %% check the ACL?

    %% For now we just always
    %% return true
    {true, RD, Ctx}.

%% @doc Parse an authentication header string and determine
%%      the appropriate module to use to authenticate the request.
%%      The passthru auth can be used either with a KeyID or
%%      anonymously by leving the header empty.
-spec parse_auth_header(string(), boolean()) -> {ok, atom(), [string()]} | {error, term()}.
parse_auth_header(KeyID, true) when KeyID =/= undefined ->
    {ok, riak_moss_passthru_auth, [KeyID]};
parse_auth_header(_, true) ->
    {ok, riak_moss_passthru_auth, []};
parse_auth_header(undefined, false) ->
    {ok, riak_moss_blockall_auth, [unkown_auth_scheme]};
parse_auth_header("AWS " ++ Key, _) ->
    case string:tokens(Key, ":") of
        [KeyId, KeyData] ->
            {ok, riak_moss_s3_auth, [KeyId, KeyData]};
        Other -> Other
    end;
parse_auth_header(_, _) ->
    {ok, riak_moss_blockall_auth, [unkown_auth_scheme]}.


%% @doc Utility function for accessing
%%      a riakc_obj without retrieving
%%      it again if it's already in the
%%      Ctx
-spec ensure_doc(term()) -> term().
ensure_doc(Ctx=#key_context{get_fsm_pid=undefined, bucket=Bucket, key=Key,
                            method=Method}) ->
    %% start the get_fsm
    BinBucket = list_to_binary(Bucket),
    BinKey = list_to_binary(Key),
    ManifestOnly = case Method of 'HEAD' -> true;
                                  _      -> false
                   end,
    {ok, Pid} = riak_moss_get_fsm_sup:start_get_fsm(
                  node(), [BinBucket, BinKey, ManifestOnly]),
    Metadata = riak_moss_get_fsm:get_metadata(Pid),
    Ctx#key_context{get_fsm_pid=Pid, doc_metadata=Metadata};
ensure_doc(Ctx) -> Ctx.

streaming_get(FsmPid) ->
    case riak_moss_get_fsm:get_next_chunk(FsmPid) of
        {done, Chunk} ->
            {Chunk, done};
        {chunk, Chunk} ->
            {Chunk, fun() -> streaming_get(FsmPid) end}
    end.

%% @doc Convert a moss_user record
%%      into a property list, likely
%%      for json encoding
-spec user_record_to_proplist(term()) -> list().
user_record_to_proplist(#moss_user{name=Name,
                                   key_id=KeyID,
                                   key_secret=KeySecret,
                                   buckets = Buckets}) ->
    [{<<"name">>, list_to_binary(Name)},
     {<<"key_id">>, list_to_binary(KeyID)},
     {<<"key_secret">>, list_to_binary(KeySecret)},
     {<<"buckets">>, Buckets}].

%% @doc Get an ISO 8601 formatted timestamp representing
%% current time.
-spec iso_8601_datetime() -> string().
iso_8601_datetime() ->
    {{Year, Month, Day}, {Hour, Min, Sec}} = erlang:universaltime(),
    iso_8601_format(Year, Month, Day, Hour, Min, Sec).

%% @doc Convert an RFC 1123 date into an ISO 8601 formatted timestamp.
-spec to_iso_8601(string()) -> string().
to_iso_8601(Date) ->
    case httpd_util:convert_request_date(Date) of
        {{Year, Month, Day}, {Hour, Min, Sec}} ->
            iso_8601_format(Year, Month, Day, Hour, Min, Sec);
        bad_date ->
            %% Date is already in ISO 8601 format
            Date
    end.

%% ===================================================================
%% Internal functions
%% ===================================================================

%% @doc Get an ISO 8601 formatted timestamp representing
%% current time.
-spec iso_8601_format(pos_integer(),
                      pos_integer(),
                      pos_integer(),
                      non_neg_integer(),
                      non_neg_integer(),
                      non_neg_integer()) -> string().
iso_8601_format(Year, Month, Day, Hour, Min, Sec) ->
    io_lib:format("~4.10.0B-~2.10.0B-~2.10.0BT~2.10.0B:~2.10.0B:~2.10.0B.000Z",
                  [Year, Month, Day, Hour, Min, Sec]).

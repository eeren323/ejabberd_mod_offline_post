-module(mod_offline_post).
-author('Diamond by BOLD').

-behaviour(gen_mod).

-export([
  start/2,
  init/2,
  stop/1,
  depends/2,
  mod_options/1,
  mod_opt_type/1,
  muc_filter_message/5,
  offline_message/1
]).

-define(PROCNAME, ?MODULE).

-include("xmpp.hrl").
-include("logger.hrl").
-include("mod_muc_room.hrl").

start(Host, Opts) ->
  ?INFO_MSG("Starting mod_offline_post", []),
  register(?PROCNAME, spawn(?MODULE, init, [Host, Opts])),
  ok.

init(Host, _Opts) ->
  inets:start(),
  ssl:start(),
  ejabberd_hooks:add(muc_filter_message, Host, ?MODULE, muc_filter_message, 10),
  ejabberd_hooks:add(offline_message_hook, Host, ?MODULE, offline_message, 10),
  ok.

stop(Host) ->
  ?INFO_MSG("Stopping mod_offline_post", []),
  ejabberd_hooks:delete(muc_filter_message, Host, ?MODULE, muc_filter_message, 10),
  ejabberd_hooks:delete(offline_message_hook, Host, ?MODULE, offline_message, 10),
  ok.

depends(_Host, _Opts) ->
  [].

mod_opt_type(post_url) -> fun binary_to_list/1;
mod_opt_type(auth_token) -> fun binary_to_list/1.

mod_options(_Host) ->
    [{post_url, undefined},
     {auth_token, ""}].

% Buggy as FromJID and RoomJID are referenced in here. Will determine if it is still needed once tested with muc
muc_filter_message(Stanza, MUCState, FromNick) ->
  PostUrl = gen_mod:get_module_opt(MUCState#state.server_host, ?MODULE, post_url),
  Token = gen_mod:get_module_opt(MUCState#state.server_host, ?MODULE, auth_token),  
  Type = xmpp:get_type(Stanza),
  BodyTxt = xmpp:get_text(Stanza#message.body),

  ?DEBUG("Receiving offline stanza with 3 arguments", []),
  %?DEBUG("Receiving offline message type ~s from ~s to ~s with body \"~s\"", [Type, FromJID#jid.luser, RoomJID#jid.luser, BodyTxt]),

  _LISTUSERS = lists:map(
    fun({_LJID, Info}) ->
      binary_to_list(Info#user.jid#jid.luser) ++ ".."
    end,
    dict:to_list(MUCState#state.users)
  ),
  ?DEBUG(" #########    GROUPCHAT _LISTUSERS = ~p~n  #######   ", [_LISTUSERS]),

  _AFILLIATIONS = lists:map(
    fun({{Uname, _Domain, _Res}, _Stuff}) ->
      binary_to_list(Uname) ++ ".."
    end,
    dict:to_list(MUCState#state.affiliations)
  ),
  ?DEBUG(" #########    GROUPCHAT _AFILLIATIONS = ~p~n  #######   ", [_AFILLIATIONS]),

  _OFFLINE = lists:subtract(_AFILLIATIONS, _LISTUSERS),
  ?DEBUG(" #########    GROUPCHAT _OFFLINE = ~p~n  #######   ", [_OFFLINE]),

  if
    BodyTxt /= "", length(_OFFLINE) > 0 ->
      Sep = "&",
      Post = [
        "type=groupchat", Sep,
        %"to=", RoomJID#jid.luser, Sep,
        %"from=", FromJID#jid.luser, Sep,
        "offline=", _OFFLINE, Sep,
        "nick=", FromNick, Sep,
        "body=", BodyTxt, Sep,
        "access_token=", Token
      ],
      ?DEBUG("Sending post request to ~s with body \"~s\"", [PostUrl, Post]),
      httpc:request(post, {PostUrl, [], "application/x-www-form-urlencoded", list_to_binary(Post)}, [], []),
      Stanza;
    true ->
      Stanza
  end.

muc_filter_message(Stanza, MUCState, RoomJID, FromJID, FromNick) ->
  PostUrl = gen_mod:get_module_opt(MUCState#state.server_host, ?MODULE, post_url),
  Token = gen_mod:get_module_opt(MUCState#state.server_host, ?MODULE, auth_token),	
  Type = xmpp:get_type(Stanza),
  BodyTxt = xmpp:get_text(Stanza#message.body),

  ?DEBUG("Receiving offline message type ~s from ~s to ~s with body \"~s\"", [Type, FromJID#jid.luser, RoomJID#jid.luser, BodyTxt]),

  _LISTUSERS = lists:map(
    fun({_LJID, Info}) ->
      binary_to_list(Info#user.jid#jid.luser) ++ ".."
    end,
    dict:to_list(MUCState#state.users)
  ),
  ?DEBUG(" #########    GROUPCHAT _LISTUSERS = ~p~n  #######   ", [_LISTUSERS]),

  _AFILLIATIONS = lists:map(
    fun({{Uname, _Domain, _Res}, _Stuff}) ->
      binary_to_list(Uname) ++ ".."
    end,
    dict:to_list(MUCState#state.affiliations)
  ),
  ?DEBUG(" #########    GROUPCHAT _AFILLIATIONS = ~p~n  #######   ", [_AFILLIATIONS]),

  _OFFLINE = lists:subtract(_AFILLIATIONS, _LISTUSERS),
  ?DEBUG(" #########    GROUPCHAT _OFFLINE = ~p~n  #######   ", [_OFFLINE]),

  if
    BodyTxt /= "", length(_OFFLINE) > 0 ->
      Sep = "&",
      Post = [
        "type=groupchat", Sep,
        "to=", RoomJID#jid.luser, Sep,
        "from=", FromJID#jid.luser, Sep,
        "offline=", _OFFLINE, Sep,
        "nick=", FromNick, Sep,
        "body=", BodyTxt, Sep,
        "access_token=", Token
      ],
      ?DEBUG("Sending post request to ~s with body \"~s\"", [PostUrl, Post]),
      httpc:request(post, {PostUrl, [], "application/x-www-form-urlencoded", list_to_binary(Post)}, [], []),
      Stanza;
    true ->
      Stanza
  end.


offline_message({_Method, Message} = Recv) ->
  Token = gen_mod:get_module_opt(Message#message.from#jid.lserver, ?MODULE, auth_token),
  PostUrl = gen_mod:get_module_opt(Message#message.from#jid.lserver, ?MODULE, post_url),
  case Message#message.body of
    [] -> ok;
    [BodyTxt] ->
      BodyText = BodyTxt#text.data,
      ?DEBUG("mod_offline_post1: TOKEN: ~p ", [Token]),
      ?DEBUG("mod_offline_post1: PostURL: ~p ", [PostUrl]),
      ?DEBUG("mod_offline_post1: Text: ~p ", [BodyText]),
      Sep = "&",
      Post = [
        "type=chat", Sep,
        "to=", Message#message.to#jid.luser, "@", Message#message.to#jid.lserver, Sep,
        "from=", Message#message.from#jid.luser, "@", Message#message.from#jid.lserver, Sep,
        "body=", BodyText, Sep,
        "access_token=", Token
      ],
      ?DEBUG("Sending post request to ~s with body \"~s\"", [PostUrl, Post]),
      httpc:request(post, {PostUrl, [], "application/x-www-form-urlencoded", list_to_binary(Post)}, [], [])
  end,
  Recv.

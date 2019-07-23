-module(payproc_errors).

-export_type([error_type       /0]).
-export_type([reason           /0]).
-export_type([static_code      /0]).
-export_type([static_error     /0]).
-export_type([static_sub_error /0]).
-export_type([dynamic_code     /0]).
-export_type([dynamic_error    /0]).
-export_type([dynamic_sub_error/0]).

-export([construct /2]).
-export([construct /3]).
-export([match     /3]).
-export([format    /2]).
-export([format_raw/1]).


-include_lib("damsel/include/dmsl_domain_thrift.hrl").
-include_lib("damsel/include/dmsl_payment_processing_errors_thrift.hrl").

%%

-type error_type() :: 'PaymentFailure' | 'RefundFailure'.
-type type() :: atom().
-type reason() :: binary().

-type static_code() :: atom() | {unknown_error, dynamic_code()}.
-type static_error() :: {static_code(), static_sub_error()}.
-type static_sub_error() ::
      {static_code(), static_sub_error()}
    | dmsl_payment_processing_errors_thrift:'GeneralFailure'()
.

-type dynamic_code() :: binary().
-type dynamic_error() :: dmsl_domain_thrift:'Failure'().
-type dynamic_sub_error() :: dmsl_domain_thrift:'SubFailure'() | undefined.

%%

-spec construct(error_type(), static_error()) ->
    dynamic_error().
construct(Type, SE) ->
    construct(Type, SE, undefined).

-spec construct(error_type(), static_error(), reason() | undefined) ->
    dynamic_error().
construct(Type, SE, Reason) ->
    DE = error_to_dynamic(Type, SE),
    DE#domain_Failure{reason = Reason}.

-spec match(error_type(), dynamic_error(), fun((static_error()) -> R)) ->
    R.
match(Type, DE, MatchFun) ->
    MatchFun(error_to_static(Type, DE)).

-spec format(error_type(), dynamic_error()) ->
    iolist().
format(Type, DE) ->
    format_raw(error_to_dynamic(Type, error_to_static(Type, DE))).

-spec format_raw(dynamic_error()) ->
    iolist().
format_raw(#domain_Failure{code = Code, sub = Sub}) ->
    join(Code, format_sub_error_code(Sub)).

%%

-spec error_to_static(error_type(), dynamic_error()) ->
    static_error().
error_to_static(Type, #domain_Failure{code = Code, sub = SDE}) ->
    to_static(Code, Type, SDE).

-spec sub_error_to_static(type(), dynamic_sub_error()) ->
    static_sub_error().
sub_error_to_static(_, undefined) ->
    #payprocerr_GeneralFailure{};
sub_error_to_static(Type, #domain_SubFailure{code = Code, sub = SDE}) ->
    to_static(Code, Type, SDE).

-spec to_static(dynamic_code(), type(), dynamic_sub_error()) ->
    {static_code(), static_sub_error()}.
to_static(Code, Type, SDE) ->
    StaticCode = code_to_static(Code),
    case type_by_field(StaticCode, Type) of
        SubType when SubType =/= undefined ->
            {StaticCode, sub_error_to_static(SubType, SDE)};
        undefined ->
            {{unknown_error, Code}, #payprocerr_GeneralFailure{}}
    end.

-spec code_to_static(dynamic_code()) ->
    static_code().
code_to_static(Code) ->
    try
        erlang:binary_to_existing_atom(Code, utf8)
    catch error:badarg ->
        {unknown_error, Code}
    end.

%%

-spec error_to_dynamic(error_type(), static_error()) ->
    dynamic_error().
error_to_dynamic(Type, SE) ->
    {Code, SubType, SSE} = to_dynamic(Type, SE),
    #domain_Failure{code = Code, sub = sub_error_to_dynamic(SubType, SSE)}.

-spec sub_error_to_dynamic(type(), static_sub_error()) ->
    dynamic_sub_error().
sub_error_to_dynamic(undefined, _) ->
    undefined;
sub_error_to_dynamic(Type, SSE) ->
    {Code, SubType, SSE_} = to_dynamic(Type, SSE),
    #domain_SubFailure{code = Code, sub = sub_error_to_dynamic(SubType, SSE_)}.

-spec code_to_dynamic(static_code()) ->
    dynamic_code().
code_to_dynamic({unknown_error, Code}) ->
    Code;
code_to_dynamic(Code) ->
    erlang:atom_to_binary(Code, utf8).

%%

-spec to_dynamic(type(), static_sub_error()) ->
    {dynamic_code(), type() | undefined, static_sub_error()}.
to_dynamic(_, {Code = {unknown_error, _}, #payprocerr_GeneralFailure{}}) ->
    {code_to_dynamic(Code), undefined, undefined};
to_dynamic(Type, {Code, #payprocerr_GeneralFailure{}}) ->
    'GeneralFailure' = check_type(type_by_field(Code, Type)),
    {code_to_dynamic(Code), undefined, undefined};
to_dynamic(Type, {Code, SSE}) ->
    {code_to_dynamic(Code), check_type(type_by_field(Code, Type)), SSE}.

-spec check_type(type() | undefined) ->
    type() | no_return().
check_type(undefined) ->
    erlang:error(badarg);
check_type(Type) ->
    Type.

%%

-spec format_sub_error_code(dynamic_sub_error()) ->
    iolist().
format_sub_error_code(undefined) ->
    [];
format_sub_error_code(#domain_SubFailure{code = Code, sub = Sub}) ->
    join(Code, format_sub_error_code(Sub)).

-spec join(binary(), iolist()) ->
    iolist().
join(Code, [] ) -> [Code];
join(Code, Sub) -> [Code, $:, Sub].

%%

-spec type_by_field(static_code(), type()) ->
    atom() | undefined.
type_by_field(Code, Type) ->
    case [Field || Field = {Code_, _} <- struct_info(Type), Code =:= Code_] of
        [{_, SubType}] -> SubType;
        [            ] -> undefined
    end.

-spec struct_info(atom()) ->
    [{atom(), atom()}].
struct_info(Type) ->
    {struct, _, Fs} = dmsl_payment_processing_errors_thrift:struct_info(Type),
    [{FN, FT} || {_, _, {struct, _, {'dmsl_payment_processing_errors_thrift', FT}}, FN, _} <- Fs].

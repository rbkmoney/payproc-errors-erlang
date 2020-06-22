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
-include_lib("damsel/include/dmsl_withdrawals_errors_thrift.hrl").

%%

-type error_type() :: 'PaymentFailure' | 'RefundFailure' | 'WithdrawalFailure'.
-type error_namespace() :: payment_processing_errors | withdrawals_errors.
-type type() :: atom().
-type reason() :: binary().

-type static_code() :: atom() | {unknown_error, dynamic_code()}.
-type static_error() :: {static_code(), static_sub_error()}.
-type static_sub_error() ::
      {static_code(), static_sub_error()}
    | dmsl_payment_processing_errors_thrift:'GeneralFailure'()
    | dmsl_withdrawals_errors_thrift:'GeneralFailure'()
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
    NS = error_type_namespace(Type),
    to_static(NS, Code, Type, SDE).

-spec sub_error_to_static(error_namespace(), type(), dynamic_sub_error()) ->
    static_sub_error().
sub_error_to_static(NS, _Type, undefined) ->
    general_error(NS);
sub_error_to_static(NS, Type, #domain_SubFailure{code = Code, sub = SDE}) ->
    to_static(NS, Code, Type, SDE).

-spec to_static(error_namespace(), dynamic_code(), type(), dynamic_sub_error()) ->
    {static_code(), static_sub_error()}.
to_static(NS, Code, Type, SDE) ->
    StaticCode = code_to_static(Code),
    case type_by_field(NS, StaticCode, Type) of
        SubType when SubType =/= undefined ->
            {StaticCode, sub_error_to_static(NS, SubType, SDE)};
        undefined ->
            {{unknown_error, Code}, general_error(NS)}
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
    NS = error_type_namespace(Type),
    {Code, SubType, SSE} = to_dynamic(NS, Type, SE),
    #domain_Failure{code = Code, sub = sub_error_to_dynamic(NS, SubType, SSE)}.

-spec sub_error_to_dynamic(error_namespace(), type(), static_sub_error()) ->
    dynamic_sub_error().
sub_error_to_dynamic(_, undefined, _) ->
    undefined;
sub_error_to_dynamic(NS, Type, SSE) ->
    {Code, SubType, SSE_} = to_dynamic(NS, Type, SSE),
    #domain_SubFailure{code = Code, sub = sub_error_to_dynamic(NS, SubType, SSE_)}.

-spec code_to_dynamic(static_code()) ->
    dynamic_code().
code_to_dynamic({unknown_error, Code}) ->
    Code;
code_to_dynamic(Code) ->
    erlang:atom_to_binary(Code, utf8).

%%

-spec to_dynamic(error_namespace(), type(), static_sub_error()) ->
    {dynamic_code(), type() | undefined, static_sub_error()}.
to_dynamic(_, _, {Code = {unknown_error, _}, _}) ->
    {code_to_dynamic(Code), undefined, undefined};
to_dynamic(NS, Type, {Code, SSE}) when
    SSE =:= #payprocerr_GeneralFailure{};
    SSE =:= #wtherr_GeneralFailure{}
->
    'GeneralFailure' = check_type(type_by_field(NS, Code, Type)),
    {code_to_dynamic(Code), undefined, undefined};
to_dynamic(NS, Type, {Code, SSE}) ->
    {code_to_dynamic(Code), check_type(type_by_field(NS, Code, Type)), SSE}.

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

error_type_namespace(Type) when
    Type =:= 'PaymentFailure';
    Type =:= 'RefundFailure'
->
    payment_processing_errors;
error_type_namespace(Type) when
    Type =:= 'WithdrawalFailure'
->
    withdrawals_errors.

error_type_module(payment_processing_errors) ->
    'dmsl_payment_processing_errors_thrift';
error_type_module(withdrawals_errors) ->
    'dmsl_withdrawals_errors_thrift'.

general_error(payment_processing_errors) ->
    #payprocerr_GeneralFailure{};
general_error(withdrawals_errors) ->
    #wtherr_GeneralFailure{}.

-spec type_by_field(error_namespace(), static_code(), type()) ->
    atom() | undefined.
type_by_field(NS, Code, Type) ->
    case [Field || Field = {Code_, _} <- struct_info(NS, Type), Code =:= Code_] of
        [{_, SubType}] -> SubType;
        [            ] -> undefined
    end.

-spec struct_info(error_namespace(), atom()) ->
    [{atom(), atom()}].
struct_info(NS, Type) ->
    Module = error_type_module(NS),
    {struct, _, Fs} = Module:struct_info(Type),
    [{FN, FT} || {_, _, {struct, _, {_Module, FT}}, FN, _} <- Fs].

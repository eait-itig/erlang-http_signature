%% -*- mode: erlang; tab-width: 4; indent-tabs-mode: 1; st-rulers: [70] -*-
%% vim: ts=4 sw=4 ft=erlang noet
%%%-------------------------------------------------------------------
%%% @author Andrew Bennett <andrew@pixid.com>
%%% @author Alex Wilson <alex@uq.edu.au>
%%% @copyright 2014-2017, Andrew Bennett
%%% @copyright 2019, The University of Queensland
%%% @doc
%%%
%%% @end
%%% Created :  06 Oct 2017 by Andrew Bennett <andrew@pixid.com>
%%% Modified to use the Joyent variant of ECDSA signatures
%%%-------------------------------------------------------------------
-module(http_signature_ecdsa).
-behaviour(http_signature_algorithm).

-include("http_signature_utils.hrl").
-include_lib("public_key/include/public_key.hrl").

%% http_signature_algorithm callbacks
-export([default_sign_algorithm/1]).
-export([encode_pem/1]).
-export([encode_pem/2]).
-export([generate_key/1]).
-export([sign/3]).
-export([verify/4]).

%%%===================================================================
%%% http_signature_algorithm callbacks
%%%===================================================================

default_sign_algorithm(#'ECPrivateKey'{parameters=ECParameters}) ->
    NamedCurve = ec_parameters_to_named_curve(ECParameters),
    Size = ec_named_curve_to_size(NamedCurve),
    case Size of
        _ when Size =< 32 -> <<"ecdsa-sha256">>;
        _ when Size =< 48 -> <<"ecdsa-sha384">>;
        _ -> <<"ecdsa-sha512">>
    end.

encode_pem(ECPrivateKey = #'ECPrivateKey'{}) ->
    PEMEntry = http_signature_public_key:pem_entry_encode('ECPrivateKey', ECPrivateKey),
    http_signature_public_key:pem_encode([PEMEntry]);
encode_pem(ECPublicKey = {#'ECPoint'{}, _}) ->
    PEMEntry = http_signature_public_key:pem_entry_encode('SubjectPublicKeyInfo', ECPublicKey),
    http_signature_public_key:pem_encode([PEMEntry]).

encode_pem(ECPrivateKey = #'ECPrivateKey'{}, Password) ->
    CipherInfo = {"AES-128-CBC", crypto:strong_rand_bytes(16)},
    PasswordString = erlang:binary_to_list(erlang:iolist_to_binary(Password)),
    PEMEntry = http_signature_public_key:pem_entry_encode('ECPrivateKey', ECPrivateKey, {CipherInfo, PasswordString}),
    http_signature_public_key:pem_encode([PEMEntry]).

generate_key(#'ECPrivateKey'{ parameters = P }) ->
    generate_key(P);
generate_key({#'ECPoint'{}, P}) ->
    generate_key(P);
generate_key(ECParameters = #'ECParameters'{}) ->
    public_key:generate_key(ECParameters);
generate_key(NamedCurve) when is_atom(NamedCurve) ->
    generate_key({namedCurve, pubkey_cert_records:namedCurves(NamedCurve)});
generate_key(NamedCurve) when is_binary(NamedCurve) ->
    generate_key(http_signature_public_key:ec_domain_parameters_to_named_curve(NamedCurve));
generate_key({namedCurve, NamedCurve}) when is_atom(NamedCurve) orelse is_binary(NamedCurve) ->
    generate_key(NamedCurve);
generate_key(NamedCurve = {namedCurve, _}) ->
    public_key:generate_key(NamedCurve).

sign(ECPrivateKey=#'ECPrivateKey'{}, Algorithm, Message) ->
    DigestType = algorithm_to_digest_type(Algorithm),
    public_key:sign(Message, DigestType, ECPrivateKey).

verify(ECPublicKey={#'ECPoint'{}, _}, Algorithm, Signature, Message) ->
    DigestType = algorithm_to_digest_type(Algorithm),
    public_key:verify(Message, DigestType, Signature, ECPublicKey).

%%%-------------------------------------------------------------------
%%% Internal functions
%%%-------------------------------------------------------------------

%% @private
algorithm_to_digest_type(Algorithm) ->
    case Algorithm of
        <<"ecdsa-sha1">> -> sha;
        <<"ecdsa-sha224">> -> sha224;
        <<"ecdsa-sha256">> -> sha256;
        <<"ecdsa-sha384">> -> sha384;
        <<"ecdsa-sha512">> -> sha512;
        _ -> ?http_signature_throw({bad_algorithm, Algorithm}, "Bad algorithm for ECDSA key: ~s", [Algorithm])
    end.

%% @private
ec_named_curve_to_size(secp256r1) -> 32;
ec_named_curve_to_size(secp384r1) -> 48;
ec_named_curve_to_size(secp521r1) -> 66;
ec_named_curve_to_size(sect163k1) -> 21;
ec_named_curve_to_size(secp192r1) -> 24;
ec_named_curve_to_size(secp224r1) -> 28;
ec_named_curve_to_size(sect233k1) -> 30;
ec_named_curve_to_size(sect233r1) -> 30;
ec_named_curve_to_size(sect283k1) -> 36;
ec_named_curve_to_size(sect409k1) -> 52;
ec_named_curve_to_size(sect409r1) -> 52;
ec_named_curve_to_size(sect571k1) -> 72.

%% @private
ec_parameters_to_named_curve({namedCurve, P}) ->
    pubkey_cert_records:namedCurves(P);
ec_parameters_to_named_curve(P) ->
    P.

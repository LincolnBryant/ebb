-module(ebb_dhcp_lib).
-moduledoc "Handles DHCP packets".

-export([decode_request/1]).

-include("dhcp.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% DHCP Message Types - Option 53
%-define(DHCPDISCOVER, 1).
%-define(DHCPOFFER, 2).
%-define(DHCPREQUEST, 3).
%-define(DHCPDECLINE, 4).
%-define(DHCPACK, 5).
%-define(DHCPNAK, 6).
%-define(DHCPRELASE, 7).
%-define(DHCPINFORM, 8).

-spec decode_request(binary()) -> dhcp_message().
decode_request(
    <<1:8, HType:8, HLen:8, Hops:8, Xid:32, Secs:16, Flags:2/binary, CiAddr:32,
        YiAddr:32, SiAddr:32, GiAddr:32, ChAddr:16/binary, SName:64/binary,
        File:128/binary, ?DHCP_MAGIC_COOKIE:32, OptRaw/binary>>
) ->
    #dhcp_message{
        op = bootrequest,
        htype = HType,
        hlen = HLen,
        hops = Hops,
        xid = Xid,
        secs = Secs,
        flags = decode_flags(Flags),
        ciaddr = decode_ip(CiAddr),
        yiaddr = decode_ip(YiAddr),
        siaddr = decode_ip(SiAddr),
        giaddr = decode_ip(GiAddr),
        chaddr = decode_mac(ChAddr),
        sname = SName,
        file = File,
        options = decode_option_list(OptRaw)
    }.

% DHCPv4 only defines a broadcast flag in the 16-bit field. It's either on or off.
decode_flags(<<1:1, _:15>>) -> [broadcast];
decode_flags(<<_:16>>) -> [].

decode_ip(0) ->
    % can be zero
    {0, 0, 0, 0};
decode_ip(<<A:8, B:8, C:8, D:8>>) ->
    {A, B, C, D}.

decode_mac(<<A:8, B:8, C:8, D:8, E:8, F:8>>) ->
    {A, B, C, D, E, F};
decode_mac(<<A:8, B:8, C:8, D:8, E:8, F:8, _Padding:10/binary>>) ->
    {A, B, C, D, E, F}.

decode_tlv(Bin, DecodeFun) ->
    decode_tlv(Bin, DecodeFun, []).
decode_tlv(<<>>, _, Acc) ->
    lists:reverse(Acc);
decode_tlv(<<255, _Rest/binary>>, _, Acc) ->
    lists:reverse(Acc);
decode_tlv(<<Tag, Len, Value:Len/binary, Rest/binary>>, F, Acc) ->
    decode_tlv(Rest, F, [F(Tag, Value) | Acc]);
decode_tlv(_Malformed, _, Acc) ->
    lists:reverse(Acc).

decode_option_list(Bin) ->
    decode_tlv(Bin, fun decode_option/2).

decode_option(53, <<Type>>) ->
    {message_type, decode_msgtype(Type)};
decode_option(55, Bin) ->
    {parameter_list, binary_to_list(Bin)};
decode_option(57, <<Size:16>>) ->
    {max_message_size, Size};
decode_option(60, Bin) ->
    {vendor_class_id, Bin};
decode_option(61, <<1, Addr/binary>>) ->
    {client_id, {ethernet, decode_mac(Addr)}};
decode_option(93, <<Arch:16>>) ->
    {client_system, decode_arch(Arch)};
decode_option(94, <<T, Maj, Min>>) ->
    {client_ndi, {T, Maj, Min}};
decode_option(77, Bin) ->
    {user_class, Bin};
decode_option(97, <<0, GUID:16/binary>>) ->
    {client_uuid, GUID};
decode_option(175, Bin) ->
    {ipxe_encap, decode_ipxe_suboption_list(Bin)};
decode_option(Tag, Val) ->
    logger:debug("Not implemented: {~p,~p}", [Tag, Val]),
    {Tag, Val}.

decode_msgtype(1) ->
    dhcpdiscover;
decode_msgtype(2) ->
    dhcpoffer;
decode_msgtype(3) ->
    dhcprequest;
decode_msgtype(4) ->
    dhpcdecline;
decode_msgtype(5) ->
    dhcpack;
decode_msgtype(6) ->
    dhcpnak;
decode_msgtype(7) ->
    dhcprelease;
decode_msgtype(8) ->
    dhcpinform;
decode_msgtype(9) ->
    dhcpforcerenew;
decode_msgtype(10) ->
    dhcpleasequery;
decode_msgtype(11) ->
    dhcpleaseunassigned;
decode_msgtype(12) ->
    dhcpleaseunknown;
decode_msgtype(13) ->
    dhcpleaseactive;
decode_msgtype(14) ->
    dhcpbulkleasequery;
decode_msgtype(15) ->
    dhcpleasequerydone;
decode_msgtype(16) ->
    dhcpactiveleasequery;
decode_msgtype(17) ->
    dhcpleasequerystatus;
decode_msgtype(18) ->
    dhcptls;
decode_msgtype(Type) ->
    logger:debug("Decoding message type ~p not implemented", [Type]),
    Type.

decode_ipxe_suboption_list(Bin) ->
    decode_tlv(Bin, fun decode_ipxe_suboption/2).

decode_arch(0) ->
    x86_bios;
decode_arch(1) ->
    nec_pc98;
decode_arch(2) ->
    efi_itanium;
decode_arch(3) ->
    dec_alpha;
decode_arch(4) ->
    arc_x86;
decode_arch(5) ->
    intel_lean_client;
decode_arch(6) ->
    efi_ia32;
decode_arch(7) ->
    efi_bc;
decode_arch(8) ->
    efi_xscale;
decode_arch(9) ->
    efi_x86_64;
decode_arch(N) ->
    logger:debug("Decoding arch ~p not implemented", [N]),
    N.

decode_ipxe_suboption(177, Bin) ->
    {pxext, [decode_ipxe_feature(B) || <<B>> <= Bin]};
decode_ipxe_suboption(235, <<Maj, Min, _/binary>>) ->
    {version, {Maj, Min}};
decode_ipxe_suboption(16, <<N>>) ->
    {busid, N};
decode_ipxe_suboption(17, <<N>>) ->
    {bios_drive, N};
decode_ipxe_suboption(Tag, <<1>>) ->
    {decode_ipxe_feature(Tag), true};
decode_ipxe_suboption(Tag, <<0>>) ->
    {decode_ipxe_feature(Tag), false};
decode_ipxe_suboption(Tag, Value) ->
    {decode_ipxe_feature(Tag), Value}.

decode_ipxe_feature(16) -> busid;
decode_ipxe_feature(17) -> bios_drive;
decode_ipxe_feature(18) -> uuid;
decode_ipxe_feature(19) -> dns;
decode_ipxe_feature(20) -> cert;
decode_ipxe_feature(21) -> crosscert;
decode_ipxe_feature(23) -> ntp;
decode_ipxe_feature(24) -> pci;
decode_ipxe_feature(25) -> smbios;
decode_ipxe_feature(33) -> http;
decode_ipxe_feature(34) -> https;
decode_ipxe_feature(38) -> skip_san_boot;
decode_ipxe_feature(39) -> iscsi;
decode_ipxe_feature(41) -> aoe;
decode_ipxe_feature(128) -> bzimage;
decode_ipxe_feature(134) -> comboot;
decode_ipxe_feature(177) -> pxext;
decode_ipxe_feature(235) -> version;
decode_ipxe_feature(N) -> N.

-ifdef(TEST).
discover_test() ->
    DiscoverPacket =
        <<1, 1, 6, 0, 57, 197, 214, 111, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 82, 84, 0, 18, 52, 86, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            99, 130, 83, 99, 53, 1, 1, 57, 2, 5, 192, 93, 2, 0, 0, 94, 3, 1, 2, 1,
            60, 32, 80, 88, 69, 67, 108, 105, 101, 110, 116, 58, 65, 114, 99, 104,
            58, 48, 48, 48, 48, 48, 58, 85, 78, 68, 73, 58, 48, 48, 50, 48, 48, 49,
            77, 4, 105, 80, 88, 69, 55, 25, 1, 3, 6, 7, 12, 15, 17, 26, 42, 43, 60,
            66, 67, 119, 121, 128, 129, 130, 131, 132, 133, 134, 135, 175, 203, 175,
            54, 177, 5, 1, 128, 134, 16, 14, 235, 3, 2, 0, 0, 38, 1, 1, 23, 1, 1,
            39, 1, 1, 34, 1, 1, 19, 1, 1, 20, 1, 1, 17, 1, 1, 25, 1, 1, 41, 1, 1,
            16, 1, 2, 33, 1, 1, 21, 1, 1, 18, 1, 1, 24, 1, 1, 61, 7, 1, 82, 84, 0,
            18, 52, 86, 97, 17, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            255>>,

    ?assertEqual(discover, message(DiscoverPacket)).
-endif.

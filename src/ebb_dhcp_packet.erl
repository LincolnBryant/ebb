-module(ebb_dhcp_packet).
-moduledoc "Handles DHCP packets".

-export([decode/1, encode/1]).
% Test funs ..
% -export([decode_part/1]).
% -export([encode_part/1]).
%

-include("dhcp.hrl").

-doc """
Decodes a DHCP packet into a #dhcp_message{} record. Fields are deserialized
into Erlang types where possible. Not all sub-options are exhaustively
deserialized. In such cases, the binary is passed through to the consumer.
""".
-spec decode(binary()) -> dhcp_message().
decode(
    <<Op:8, HType:8, HLen:8, Hops:8, Xid:32, Secs:16, Flags:2/binary,
        CiAddr:4/binary, YiAddr:4/binary, SiAddr:4/binary, GiAddr:4/binary,
        ChAddr:16/binary, SName:64/binary, File:128/binary, ?DHCP_MAGIC_COOKIE:32,
        OptRaw/binary>>
) ->
    #dhcp_message{
        op = decode_op(Op),
        htype = decode_htype(HType),
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

% Commented for testing
%decode_part(
%    <<Op:8, HType:8, HLen:8, Hops:8, Xid:32, Secs:16, Flags:2/binary,
%        CiAddr:4/binary, YiAddr:4/binary, SiAddr:4/binary, GiAddr:4/binary,
%        ChAddr:16/binary, SName:64/binary, File:128/binary, ?DHCP_MAGIC_COOKIE:32,
%        OptRaw/binary>>
%) ->
%    [
%        Op,
%        HType,
%        HLen,
%        Hops,
%        Xid,
%        Secs,
%        Flags,
%        CiAddr,
%        YiAddr,
%        SiAddr,
%        GiAddr,
%        ChAddr,
%        SName,
%        File,
%        OptRaw
%    ].
%
%encode_part(#dhcp_message{
%    op = Op,
%    htype = HType,
%    hlen = HLen,
%    hops = Hops,
%    xid = Xid,
%    secs = Secs,
%    flags = Flags,
%    ciaddr = CiAddr,
%    yiaddr = YiAddr,
%    siaddr = SiAddr,
%    giaddr = GiAddr,
%    chaddr = ChAddr,
%    sname = SName,
%    file = File,
%    options = Options
%}) ->
%    [
%        Op,
%        HType,
%        HLen,
%        Hops,
%        Xid,
%        Secs,
%        Flags,
%        CiAddr,
%        YiAddr,
%        SiAddr,
%        GiAddr,
%        ChAddr,
%        SName,
%        File,
%        Options
%    ].
%
-doc """
Encodes a #dhcp_message{} record into a DHCP packet. Fields are serialized per
RFC 2131, section 2: https://datatracker.ietf.org/doc/html/rfc2131#section-2
""".
-spec encode(dhcp_message()) -> binary().
encode(#dhcp_message{
    op = Op,
    htype = HType,
    hlen = HLen,
    hops = Hops,
    xid = Xid,
    secs = Secs,
    flags = Flags,
    ciaddr = CiAddr,
    yiaddr = YiAddr,
    siaddr = SiAddr,
    giaddr = GiAddr,
    chaddr = ChAddr,
    sname = SName,
    file = File,
    options = Options
}) ->
    OpBin = encode_uint8(encode_op(Op)),
    HTypeBin = encode_uint8(encode_htype(HType)),
    HLenBin = encode_uint8(HLen),
    HopsBin = encode_uint8(Hops),
    XidBin = encode_uint32(Xid),
    SecsBin = encode_uint16(Secs),
    FlagsBin = encode_flags(Flags),
    CiAddrBin = encode_ip(CiAddr),
    YiAddrBin = encode_ip(YiAddr),
    SiAddrBin = encode_ip(SiAddr),
    GiAddrBin = encode_ip(GiAddr),
    % 10 bytes of padding
    ChAddrBin = <<(encode_mac(ChAddr))/binary, 0:80>>,
    SNameBin = encode_padded_string(SName, 64),
    FileBin = encode_padded_string(File, 128),
    OptionsBin = encode_option_list(Options),
    <<OpBin/binary, HTypeBin/binary, HLenBin/binary, HopsBin/binary, XidBin/binary,
        SecsBin/binary, FlagsBin/binary, CiAddrBin/binary, YiAddrBin/binary,
        SiAddrBin/binary, GiAddrBin/binary, ChAddrBin/binary, SNameBin/binary,
        FileBin/binary, ?DHCP_MAGIC_COOKIE:32, OptionsBin/binary>>.

% Useful encoding helpers

encode_uint8(N) when N >= 0, N =< 16#FF -> <<N:8>>.
encode_uint16(N) when N >= 0, N =< 16#FFFF -> <<N:16>>.
encode_uint32(N) when N >= 0, N =< 16#FFFFFFFF -> <<N:32>>.

-doc """
Encode a string as a binary up to Size bytes. Strings are null terminated, and
values beyond Size-1 bytes are truncated.
""".
-spec encode_padded_string(binary(), pos_integer()) -> binary().
encode_padded_string(<<>>, Size) ->
    <<0:(Size * 8)>>;
encode_padded_string(Str, Size) when byte_size(Str) =< Size - 1 ->
    PadLen = Size - byte_size(Str),
    <<Str/binary, 0:(PadLen * 8)>>;
encode_padded_string(Str, Size) when byte_size(Str) >= Size ->
    <<Truncated:(Size - 1)/binary, _/binary>> = Str,
    <<Truncated/binary, 0:8>>.

-doc """
Decodes the message op copde into an Erlang atom. Only 1 = 'bootrequest' and 2
= 'bootreply' are understood per
https://www.rfc-editor.org/info/rfc2131/#section-2
""".
-spec decode_op(1..2) -> op().
decode_op(1) -> bootrequest;
decode_op(2) -> bootreply.

-doc """
Encodes the message op copde into an Erlang atom. Only 'bootrequest' = 1 and
'bootreply' = 2 are understood per
https://www.rfc-editor.org/info/rfc2131/#section-2
""".
-spec encode_op(op()) -> 1..2.
encode_op(bootrequest) ->
    1;
encode_op(bootreply) ->
    2.

-doc """
Decodes a DHCP hardware type per
https://www.iana.org/assignments/arp-parameters/arp-parameters.xhtml#arp-parameters-2
and returns an atom. Unknown hardware types are returned as their integer value.
""".
-spec decode_htype(0..16#FFFF) -> htype().
decode_htype(16#00) -> reserved;
decode_htype(16#01) -> ethernet;
decode_htype(16#02) -> experimental_ethernet;
decode_htype(16#03) -> ax25;
decode_htype(16#04) -> proteon_pronet_token_ring;
decode_htype(16#05) -> chaos;
decode_htype(16#06) -> ieee802;
decode_htype(16#07) -> arcnet;
decode_htype(16#08) -> hyperchannel;
decode_htype(16#09) -> lanstar;
decode_htype(16#0A) -> autonet_short_address;
decode_htype(16#0B) -> localtalk;
decode_htype(16#0C) -> localnet;
decode_htype(16#0D) -> ultra_link;
decode_htype(16#0E) -> smds;
decode_htype(16#0F) -> frame_relay;
decode_htype(16#10) -> atm_16;
decode_htype(16#11) -> hdlc;
decode_htype(16#12) -> fibre_channel;
decode_htype(16#13) -> atm_19;
decode_htype(16#14) -> serial_line;
decode_htype(16#15) -> atm_21;
decode_htype(16#16) -> mil_std_188_220;
decode_htype(16#17) -> metricom;
decode_htype(16#18) -> ieee1394;
decode_htype(16#19) -> mapos;
decode_htype(16#1A) -> twinaxial;
decode_htype(16#1B) -> eui64;
decode_htype(16#1C) -> hiparp;
decode_htype(16#1D) -> ip_arp_iso_7816_3;
decode_htype(16#1E) -> arpsec;
decode_htype(16#1F) -> ipsec_tunnel;
decode_htype(16#20) -> infiniband;
decode_htype(16#21) -> tia_102_p25_cai;
decode_htype(16#22) -> wiegand_interface;
decode_htype(16#23) -> pure_ip;
decode_htype(16#24) -> hw_exp1;
decode_htype(16#26) -> unified_bus;
decode_htype(N) when is_integer(N), N >= 0, N =< 16#FFFF -> N.

-doc """
Encodes a DHCP hardware type, which is sourced from the the ARP hardware types
from
https://www.iana.org/assignments/arp-parameters/arp-parameters.xhtml#arp-parameters-2
N.b. that DHCPv4 reserves only 8 bits for hardware types, while ARP reserves
16-bits. Unknown htypes or htypes beyond 255 will cause a crash.
""".
-spec encode_htype(htype()) -> 0..16#FF.
encode_htype(reserved) -> 16#00;
encode_htype(ethernet) -> 16#01;
encode_htype(experimental_ethernet) -> 16#02;
encode_htype(ax25) -> 16#03;
encode_htype(proteon_pronet_token_ring) -> 16#04;
encode_htype(chaos) -> 16#05;
encode_htype(ieee802) -> 16#06;
encode_htype(arcnet) -> 16#07;
encode_htype(hyperchannel) -> 16#08;
encode_htype(lanstar) -> 16#09;
encode_htype(autonet_short_address) -> 16#0A;
encode_htype(localtalk) -> 16#0B;
encode_htype(localnet) -> 16#0C;
encode_htype(ultra_link) -> 16#0D;
encode_htype(smds) -> 16#0E;
encode_htype(frame_relay) -> 16#0F;
encode_htype(atm_16) -> 16#10;
encode_htype(hdlc) -> 16#11;
encode_htype(fibre_channel) -> 16#12;
encode_htype(atm_19) -> 16#13;
encode_htype(serial_line) -> 16#14;
encode_htype(atm_21) -> 16#15;
encode_htype(mil_std_188_220) -> 16#16;
encode_htype(metricom) -> 16#17;
encode_htype(ieee1394) -> 16#18;
encode_htype(mapos) -> 16#19;
encode_htype(twinaxial) -> 16#1A;
encode_htype(eui64) -> 16#1B;
encode_htype(hiparp) -> 16#1C;
encode_htype(ip_arp_iso_7816_3) -> 16#1D;
encode_htype(arpsec) -> 16#1E;
encode_htype(ipsec_tunnel) -> 16#1F;
encode_htype(infiniband) -> 16#20;
encode_htype(tia_102_p25_cai) -> 16#21;
encode_htype(wiegand_interface) -> 16#22;
encode_htype(pure_ip) -> 16#23;
encode_htype(hw_exp1) -> 16#24;
encode_htype(hfi) -> 16#25.

-doc """
Decodes flags per https://www.rfc-editor.org/info/rfc2131/#page-11. If the
highest bit is set, [broadcast] is returned. All other bits currently return an
empty list, but should be modified if a future RFC changes this behavior.
""".
-spec decode_flags(<<_:16>>) -> dhcp_flags().
decode_flags(<<1:1, _:15>>) -> [broadcast];
decode_flags(<<_:16>>) -> [].

-doc """
Encodes the broadcast flag, or no flags per
https://www.rfc-editor.org/info/rfc2131/#page-11. Should be modified if a
future RFC changes this behavior.
""".
-spec encode_flags(dhcp_flags()) -> <<_:16>>.
encode_flags([broadcast]) ->
    <<16#8000:16>>;
encode_flags([]) ->
    <<16#0000:16>>.

-doc """
Decodes an IP address into a 4-tuple, as defined by inet:ip4_address().
""".
-spec decode_ip(<<_:32>>) -> inet:ip4_address().
decode_ip(<<A:8, B:8, C:8, D:8>>) ->
    {A, B, C, D}.

-doc """
Encodes a 4-tuple IP address into a 4-byte binary.
""".
-spec encode_ip(inet:ip4_address()) -> <<_:32>>.
encode_ip({A, B, C, D}) ->
    <<A:8, B:8, C:8, D:8>>.

-doc """
Decode a MAC address into a 6-tuple in a manner similar to inet:ip4_address().
Accepts either a 6-byte MAC address or a 16-byte padded MAC address per RFC
2131.
""".
-spec decode_mac(<<_:48>> | <<_:128>>) -> mac_address().
decode_mac(<<A:8, B:8, C:8, D:8, E:8, F:8>>) ->
    {A, B, C, D, E, F};
decode_mac(<<A:8, B:8, C:8, D:8, E:8, F:8, _Padding:10/binary>>) ->
    {A, B, C, D, E, F}.

-doc """
Encode a 6-tuple MAC address
""".
-spec encode_mac(mac_address()) -> <<_:48>>.
encode_mac({A, B, C, D, E, F}) ->
    <<A:8, B:8, C:8, D:8, E:8, F:8>>.

-doc "Decodes an Infiniband MAC into a 20-tuple. TBD if useful".
-spec decode_ib_mac(<<_:160>>) -> ib_mac_address().
decode_ib_mac(<<A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T>>) ->
    {A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T}.

-doc "Encodes an Infiniband MAC from a 20-tuple into a 20-byte binary".
-spec encode_ib_mac(ib_mac_address()) -> <<_:160>>.
encode_ib_mac({A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T}) ->
    <<A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T>>.

-doc """
Decode a Tag-Length-Value structure
""".
-spec decode_tlv(binary(), fun()) -> list().
decode_tlv(Bin, DecodeFun) ->
    decode_tlv(Bin, DecodeFun, []).

-spec decode_tlv(binary(), fun(), list()) -> list().
decode_tlv(<<>>, _, Acc) ->
    Acc;
decode_tlv(<<255, _Rest/binary>>, _, Acc) ->
    Acc;
decode_tlv(<<Tag, Len, Value:Len/binary, Rest/binary>>, F, Acc) ->
    decode_tlv(Rest, F, [F(Tag, Value) | Acc]).

-doc """
Encode a Tag-Length-Value structure.
""".
-spec encode_tlv([tuple()], fun()) -> binary().
encode_tlv(TupleList, EncodeFun) ->
    encode_tlv(TupleList, EncodeFun, []).

encode_tlv([], _F, Acc) ->
    <<(list_to_binary(Acc))/binary, 255>>;
encode_tlv([{Tag, Value} | Rest], F, Acc) ->
    encode_tlv(Rest, F, [F(Tag, Value) | Acc]).

decode_option_list(Bin) ->
    decode_tlv(Bin, fun decode_option/2).

encode_option_list(TupleList) ->
    encode_tlv(TupleList, fun encode_option/2).

decode_option(1, <<A, B, C, D>>) ->
    {subnet_mask, {A, B, C, D}};
decode_option(12, Bin) ->
    {host_name, Bin};
decode_option(50, <<A, B, C, D>>) ->
    {requested_ip, {A, B, C, D}};
decode_option(51, <<Secs:32>>) ->
    {lease_time, Secs};
decode_option(53, <<Type>>) ->
    {message_type, decode_msgtype(Type)};
decode_option(54, <<A, B, C, D>>) ->
    {server_id, {A, B, C, D}};
decode_option(55, Bin) ->
    {parameter_list, binary_to_list(Bin)};
decode_option(57, <<Size:16>>) ->
    {max_message_size, Size};
decode_option(60, Bin) ->
    {vendor_class_id, Bin};
decode_option(61, Bin) ->
    io:format("Pre: ~p~n", [Bin]),
    {client_id, decode_client_id(Bin)};
decode_option(93, <<Arch:16>>) ->
    {client_system, decode_arch(Arch)};
decode_option(94, <<T, Maj, Min>>) ->
    {client_ndi, {T, Maj, Min}};
decode_option(77, Bin) ->
    {user_class, Bin};
decode_option(97, <<0, GUID:16/binary>>) ->
    {client_uuid, GUID};
decode_option(125, Bin) ->
    {vivso, Bin};
decode_option(175, Bin) ->
    {ipxe_encap, decode_ipxe_suboption_list(Bin)};
decode_option(Tag, Val) ->
    logger:debug("Not implemented: {~p,~p}", [Tag, Val]),
    {Tag, Val}.

encode_option(subnet_mask, {A, B, C, D}) ->
    Bin = encode_ip({A, B, C, D}),
    Len = byte_size(Bin),
    <<1, Len, Bin/binary>>;
encode_option(host_name, Bin) ->
    Len = byte_size(Bin),
    <<12, Len, Bin/binary>>;
encode_option(requested_ip, {A, B, C, D}) ->
    Bin = encode_ip({A, B, C, D}),
    Len = byte_size(Bin),
    <<50, Len, Bin/binary>>;
encode_option(lease_time, Secs) when
    Secs >= 16#00000000, Secs =< 16#FFFFFFFF
->
    Len = 4,
    <<51, Len, Secs:32>>;
encode_option(message_type, Type) ->
    Bin = encode_uint8(encode_msgtype(Type)),
    Len = byte_size(Bin),
    <<53, Len, Bin/binary>>;
encode_option(server_id, {A, B, C, D}) ->
    Bin = encode_ip({A, B, C, D}),
    Len = byte_size(Bin),
    <<54, Len, Bin/binary>>;
encode_option(parameter_list, List) ->
    Bin = encode_parameter_list(List),
    <<55, (byte_size(Bin)), Bin/binary>>;
encode_option(max_message_size, Size) when
    Size >= 16#0000, Size =< 16#FFFF
->
    Len = 2,
    <<57, Len, Size:16>>;
encode_option(vendor_class_id, Bin) ->
    <<60, (byte_size(Bin)), Bin/binary>>;
encode_option(client_id, ClientId) ->
    Bin = encode_client_id(ClientId),
    Len = byte_size(Bin),
    <<61, Len, Bin/binary>>;
encode_option(client_system, Arch) ->
    <<93, 2, (encode_arch(Arch)):16>>;
encode_option(client_ndi, {T, Maj, Min}) ->
    <<94, 3, T, Maj, Min>>;
encode_option(user_class, Bin) ->
    <<77, (byte_size(Bin)), Bin/binary>>;
encode_option(client_uuid, GUID) ->
    <<97, 17, 0, GUID:16/binary>>;
encode_option(vivso, Bin) ->
    <<125, (byte_size(Bin)), Bin/binary>>;
encode_option(ipxe_encap, SubOpts) ->
    Bin = encode_ipxe_suboption_list(SubOpts),
    <<175, (byte_size(Bin)), Bin/binary>>.

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

encode_msgtype(dhcpdiscover) -> 1;
encode_msgtype(dhcpoffer) -> 2;
encode_msgtype(dhcprequest) -> 3;
encode_msgtype(dhcpdecline) -> 4;
encode_msgtype(dhcpack) -> 5;
encode_msgtype(dhcpnak) -> 6;
encode_msgtype(dhcprelease) -> 7;
encode_msgtype(dhcpinform) -> 8;
encode_msgtype(dhcpforcerenew) -> 9;
encode_msgtype(dhcpleasequery) -> 10;
encode_msgtype(dhcpleaseunassigned) -> 11;
encode_msgtype(dhcpleaseunknown) -> 12;
encode_msgtype(dhcpleaseactive) -> 13;
encode_msgtype(dhcpbulkleasequery) -> 14;
encode_msgtype(dhcpleasequerydone) -> 15;
encode_msgtype(dhcpactiveleasequery) -> 16;
encode_msgtype(dhcpleasequerystatus) -> 17;
encode_msgtype(dhcptls) -> 18.

encode_parameter_list(List) ->
    F = fun(N, Acc) when N >= 0, N =< 255 ->
        [N | Acc]
    end,
    List1 = lists:foldl(F, [], List),
    List2 = lists:reverse(List1),
    list_to_binary(List2).

-doc """
Per https://www.rfc-editor.org/rfc/rfc2132#section-9.14 This MAY contain
hardware addresses, but doesn't necessitate them. In such cases, the client ID
MUST be 0. In such cases, this fun simply forwards that binary data to the
caller.
""".
decode_client_id(<<16#00, Id/binary>>) ->
    {non_hardware, Id};
decode_client_id(<<16#01, Addr:6/binary>>) ->
    {ethernet, decode_mac(Addr)};
decode_client_id(<<16#20, Addr:20/binary>>) ->
    {infiniband, decode_ib_mac(Addr)};
decode_client_id(<<HType, Addr/binary>>) ->
    {HType, Addr}.

encode_client_id({non_hardware, Id}) ->
    <<16#00, Id/binary>>;
encode_client_id({ethernet, Mac}) ->
    Bin = encode_mac(Mac),
    Test = <<16#01, Bin/binary>>,
    io:format("Post: ~p~n", [Bin]),
    Test;
encode_client_id({infiniband, Mac}) ->
    Bin = encode_ib_mac(Mac),
    <<16#20, Bin/binary>>.

decode_ipxe_suboption_list(Bin) ->
    decode_tlv(Bin, fun decode_ipxe_suboption/2).

encode_ipxe_suboption_list(TupleList) ->
    encode_tlv(TupleList, fun encode_ipxe_suboption/2).

% https://www.iana.org/assignments/dhcpv6-parameters/dhcpv6-parameters.xhtml#processor-architecture
decode_arch(16#0000) ->
    x86_bios;
decode_arch(16#0001) ->
    nec_pc98;
decode_arch(16#0002) ->
    efi_itanium;
decode_arch(16#0003) ->
    dec_alpha;
decode_arch(16#0004) ->
    arc_x86;
decode_arch(16#0005) ->
    intel_lean_client;
decode_arch(16#0006) ->
    x86_uefi;
decode_arch(16#0007) ->
    x64_uefi;
decode_arch(16#0008) ->
    efi_xscale;
decode_arch(16#0009) ->
    ebc;
decode_arch(16#000A) ->
    arm_32_uefi;
decode_arch(16#000B) ->
    arm_64_uefi;
decode_arch(16#000C) ->
    powerpc_open_firmware;
decode_arch(16#000D) ->
    powerpc_epapr;
decode_arch(16#000E) ->
    power_opal_v3;
decode_arch(16#000F) ->
    x86_uefi_http;
decode_arch(16#0010) ->
    x64_uefi_http;
decode_arch(16#0011) ->
    ebc_http;
decode_arch(16#0012) ->
    arm_32_uefi_http;
decode_arch(16#0013) ->
    arm_64_uefi_http;
decode_arch(16#0014) ->
    x86_bios_http;
decode_arch(16#0015) ->
    arm_32_uboot;
decode_arch(16#0016) ->
    arm_64_uboot;
decode_arch(16#0017) ->
    arm_32_uboot_http;
decode_arch(16#0018) ->
    arm_64_uboot_http;
decode_arch(16#0019) ->
    riscv_32_uefi;
decode_arch(16#001A) ->
    riscv_32_uefi_http;
decode_arch(16#001B) ->
    riscv_64_uefi;
decode_arch(16#001C) ->
    riscv_64_uefi_http;
decode_arch(16#001D) ->
    riscv_128_uefi;
decode_arch(16#001E) ->
    riscv_128_uefi_http;
decode_arch(16#001F) ->
    s390_basic;
decode_arch(16#0020) ->
    s390_extended;
decode_arch(16#0021) ->
    mips_32_uefi;
decode_arch(16#0022) ->
    mips_64_uefi;
decode_arch(16#0023) ->
    sunway_32_uefi;
decode_arch(16#0024) ->
    sunway_64_uefi;
decode_arch(16#0025) ->
    loongarch_32_uefi;
decode_arch(16#0026) ->
    loongarch_32_uefi_http;
decode_arch(16#0027) ->
    loongarch_64_uefi;
decode_arch(16#0028) ->
    loongarch_64_uefi_http;
decode_arch(16#0029) ->
    arm_rpiboot;
decode_arch(N) when is_integer(N), N >= 0, N =< 16#FFFF ->
    logger:debug("Decoding arch ~p not implemented", [N]),
    N.

encode_arch(x86_bios) ->
    16#0000;
encode_arch(nec_pc98) ->
    16#0001;
encode_arch(efi_itanium) ->
    16#0002;
encode_arch(dec_alpha) ->
    16#0003;
encode_arch(arc_x86) ->
    16#0004;
encode_arch(intel_lean_client) ->
    16#0005;
encode_arch(x86_uefi) ->
    16#0006;
encode_arch(x64_uefi) ->
    16#0007;
encode_arch(efi_xscale) ->
    16#0008;
encode_arch(ebc) ->
    16#0009;
encode_arch(arm_32_uefi) ->
    16#000A;
encode_arch(arm_64_uefi) ->
    16#000B;
encode_arch(powerpc_open_firmware) ->
    16#000C;
encode_arch(powerpc_epapr) ->
    16#000D;
encode_arch(power_opal_v3) ->
    16#000E;
encode_arch(x86_uefi_http) ->
    16#000F;
encode_arch(x64_uefi_http) ->
    16#0010;
encode_arch(ebc_http) ->
    16#0011;
encode_arch(arm_32_uefi_http) ->
    16#0012;
encode_arch(arm_64_uefi_http) ->
    16#0013;
encode_arch(x86_bios_http) ->
    16#0014;
encode_arch(arm_32_uboot) ->
    16#0015;
encode_arch(arm_64_uboot) ->
    16#0016;
encode_arch(arm_32_uboot_http) ->
    16#0017;
encode_arch(arm_64_uboot_http) ->
    16#0018;
encode_arch(riscv_32_uefi) ->
    16#0019;
encode_arch(riscv_32_uefi_http) ->
    16#001A;
encode_arch(riscv_64_uefi) ->
    16#001B;
encode_arch(riscv_64_uefi_http) ->
    16#001C;
encode_arch(riscv_128_uefi) ->
    16#001D;
encode_arch(riscv_128_uefi_http) ->
    16#001E;
encode_arch(s390_basic) ->
    16#001F;
encode_arch(s390_extended) ->
    16#0020;
encode_arch(mips_32_uefi) ->
    16#0021;
encode_arch(mips_64_uefi) ->
    16#0022;
encode_arch(sunway_32_uefi) ->
    16#0023;
encode_arch(sunway_64_uefi) ->
    16#0024;
encode_arch(loongarch_32_uefi) ->
    16#0025;
encode_arch(loongarch_32_uefi_http) ->
    16#0026;
encode_arch(loongarch_64_uefi) ->
    16#0027;
encode_arch(loongarch_64_uefi_http) ->
    16#0028;
encode_arch(arm_rpiboot) ->
    16#0029.

decode_ipxe_suboption(16#b1, <<Type, Vendor:16, Device:16>>) ->
    {bus_id, {Type, Vendor, Device}};
decode_ipxe_suboption(16#eb, <<Maj, Min, _/binary>>) ->
    {version, {Maj, Min}};
%% Boolean treatment ONLY for the feature-marker range 0x10-0x4f.
decode_ipxe_suboption(Tag, <<1>>) when Tag >= 16#10, Tag =< 16#4f ->
    {decode_ipxe_feature(Tag), true};
decode_ipxe_suboption(Tag, <<0>>) when Tag >= 16#10, Tag =< 16#4f ->
    {decode_ipxe_feature(Tag), false};
decode_ipxe_suboption(Tag, <<Value>>) ->
    {decode_ipxe_feature(Tag), Value}.

encode_ipxe_suboption(bus_id, {Type, Vendor, Device}) ->
    VenBin = encode_uint16(Vendor),
    DevBin = encode_uint16(Device),
    <<16#B1, Type, VenBin/binary, DevBin/binary>>;
encode_ipxe_suboption(version, {Maj, Min}) ->
    MajBin = encode_uint8(Maj),
    MinBin = encode_uint8(Min),
    <<16#EB, MajBin/binary, MinBin/binary>>;
encode_ipxe_suboption(Tag, true) ->
    TagBin = encode_uint8(encode_ipxe_feature(Tag)),
    <<TagBin/binary, 1>>;
encode_ipxe_suboption(Tag, false) ->
    TagBin = encode_uint8(encode_ipxe_feature(Tag)),
    <<TagBin/binary, 0>>;
encode_ipxe_suboption(Tag, Value) ->
    TagBin = encode_uint8(encode_ipxe_feature(Tag)),
    ValBin = encode_uint8(Value),
    <<TagBin/binary, ValBin/binary>>.

decode_ipxe_feature(16#10) -> pxe_ext;
decode_ipxe_feature(16#11) -> iscsi;
decode_ipxe_feature(16#12) -> aoe;
decode_ipxe_feature(16#13) -> http;
decode_ipxe_feature(16#14) -> https;
decode_ipxe_feature(16#15) -> tftp;
decode_ipxe_feature(16#16) -> ftp;
decode_ipxe_feature(16#17) -> dns;
decode_ipxe_feature(16#18) -> bzimage;
decode_ipxe_feature(16#19) -> multiboot;
decode_ipxe_feature(16#1a) -> slam;
decode_ipxe_feature(16#1b) -> srp;
decode_ipxe_feature(16#20) -> nbi;
decode_ipxe_feature(16#21) -> pxe;
decode_ipxe_feature(16#22) -> elf;
decode_ipxe_feature(16#23) -> comboot;
decode_ipxe_feature(16#24) -> efi;
decode_ipxe_feature(16#25) -> fcoe;
decode_ipxe_feature(16#26) -> vlan;
decode_ipxe_feature(16#27) -> menu;
decode_ipxe_feature(16#28) -> sdi;
decode_ipxe_feature(16#29) -> nfs;
decode_ipxe_feature(N) -> N.

encode_ipxe_feature(pxe_ext) -> 16#10;
encode_ipxe_feature(iscsi) -> 16#11;
encode_ipxe_feature(aoe) -> 16#12;
encode_ipxe_feature(http) -> 16#13;
encode_ipxe_feature(https) -> 16#14;
encode_ipxe_feature(tftp) -> 16#15;
encode_ipxe_feature(ftp) -> 16#16;
encode_ipxe_feature(dns) -> 16#17;
encode_ipxe_feature(bzimage) -> 16#18;
encode_ipxe_feature(multiboot) -> 16#19;
encode_ipxe_feature(slam) -> 16#1a;
encode_ipxe_feature(srp) -> 16#1b;
encode_ipxe_feature(nbi) -> 16#20;
encode_ipxe_feature(pxe) -> 16#21;
encode_ipxe_feature(elf) -> 16#22;
encode_ipxe_feature(comboot) -> 16#23;
encode_ipxe_feature(efi) -> 16#24;
encode_ipxe_feature(fcoe) -> 16#25;
encode_ipxe_feature(vlan) -> 16#26;
encode_ipxe_feature(menu) -> 16#27;
encode_ipxe_feature(sdi) -> 16#28;
encode_ipxe_feature(nfs) -> 16#29.

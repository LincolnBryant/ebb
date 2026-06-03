-module(ebb_dhcp_lib).
-moduledoc "Handles DHCP packets".

-export([decode/1]).
%-export([
%		]).

-include("dhcp.hrl").

%% DHCP Message Types - Option 53
%-define(DHCPDISCOVER, 1).
%-define(DHCPOFFER, 2).
%-define(DHCPREQUEST, 3).
%-define(DHCPDECLINE, 4).
%-define(DHCPACK, 5).
%-define(DHCPNAK, 6).
%-define(DHCPRELASE, 7).
%-define(DHCPINFORM, 8).

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

decode_op(1) -> bootrequest;
decode_op(2) -> bootreply.

encode_op(bootrequest) -> 1;
encode_op(bootreply) -> 2.

decode_htype(0) -> reserved;
decode_htype(1) -> ethernet;
decode_htype(2) -> experimental_ethernet;
decode_htype(3) -> ax25;
decode_htype(4) -> proteon_pronet_token_ring;
decode_htype(5) -> chaos;
decode_htype(6) -> ieee802;
decode_htype(7) -> arcnet;
decode_htype(8) -> hyperchannel;
decode_htype(9) -> lanstar;
decode_htype(10) -> autonet_short_address;
decode_htype(11) -> localtalk;
decode_htype(12) -> localnet;
decode_htype(13) -> ultra_link;
decode_htype(14) -> smds;
decode_htype(15) -> frame_relay;
decode_htype(16) -> atm_16;
decode_htype(17) -> hdlc;
decode_htype(18) -> fibre_channel;
decode_htype(19) -> atm_19;
decode_htype(20) -> serial_line;
decode_htype(21) -> atm_21;
decode_htype(22) -> mil_std_188_220;
decode_htype(23) -> metricom;
decode_htype(24) -> ieee1394;
decode_htype(25) -> mapos;
decode_htype(26) -> twinaxial;
decode_htype(27) -> eui64;
decode_htype(28) -> hiparp;
decode_htype(29) -> ip_arp_iso_7816_3;
decode_htype(30) -> arpsec;
decode_htype(31) -> ipsec_tunnel;
decode_htype(32) -> infiniband;
decode_htype(33) -> tia_102_p25_cai;
decode_htype(34) -> wiegand_interface;
decode_htype(35) -> pure_ip;
decode_htype(36) -> hw_exp1;
decode_htype(37) -> hfi;
decode_htype(256) -> hw_exp2;
decode_htype(257) -> aethernet;
%% RFC 4361 (DHCP client-id DUID)
decode_htype(255) -> node_specific;
decode_htype(N) when is_integer(N), N >= 0, N =< 65535 -> N.

encode_htype(reserved) -> 0;
encode_htype(ethernet) -> 1;
encode_htype(experimental_ethernet) -> 2;
encode_htype(ax25) -> 3;
encode_htype(proteon_pronet_token_ring) -> 4;
encode_htype(chaos) -> 5;
encode_htype(ieee802) -> 6;
encode_htype(arcnet) -> 7;
encode_htype(hyperchannel) -> 8;
encode_htype(lanstar) -> 9;
encode_htype(autonet_short_address) -> 10;
encode_htype(localtalk) -> 11;
encode_htype(localnet) -> 12;
encode_htype(ultra_link) -> 13;
encode_htype(smds) -> 14;
encode_htype(frame_relay) -> 15;
encode_htype(atm_16) -> 16;
encode_htype(hdlc) -> 17;
encode_htype(fibre_channel) -> 18;
encode_htype(atm_19) -> 19;
encode_htype(serial_line) -> 20;
encode_htype(atm_21) -> 21;
encode_htype(mil_std_188_220) -> 22;
encode_htype(metricom) -> 23;
encode_htype(ieee1394) -> 24;
encode_htype(mapos) -> 25;
encode_htype(twinaxial) -> 26;
encode_htype(eui64) -> 27;
encode_htype(hiparp) -> 28;
encode_htype(ip_arp_iso_7816_3) -> 29;
encode_htype(arpsec) -> 30;
encode_htype(ipsec_tunnel) -> 31;
encode_htype(infiniband) -> 32;
encode_htype(tia_102_p25_cai) -> 33;
encode_htype(wiegand_interface) -> 34;
encode_htype(pure_ip) -> 35;
encode_htype(hw_exp1) -> 36;
encode_htype(hfi) -> 37;
encode_htype(node_specific) -> 255;
encode_htype(hw_exp2) -> 256;
encode_htype(aethernet) -> 257;
encode_htype(N) when is_integer(N), N >= 0, N =< 65535 -> N.

% DHCPv4 only defines a broadcast flag in the 16-bit field. It's either on or off.
decode_flags(<<1:1, _:15>>) -> [broadcast];
decode_flags(<<_:16>>) -> [].

encode_flags([broadcast]) ->
    <<16#8000:16>>;
encode_flags([]) ->
    <<16#0000:16>>.

decode_ip(0) ->
    % can be zero
    {0, 0, 0, 0};
decode_ip(<<A:8, B:8, C:8, D:8>>) ->
    {A, B, C, D}.

encode_ip({A, B, C, D}) ->
    <<A:8, B:8, C:8, D:8>>.

decode_mac(<<A:8, B:8, C:8, D:8, E:8, F:8>>) ->
    {A, B, C, D, E, F};
decode_mac(<<A:8, B:8, C:8, D:8, E:8, F:8, _Padding:10/binary>>) ->
    {A, B, C, D, E, F}.

encode_mac({A, B, C, D, E, F}) ->
    <<A:8, B:8, C:8, D:8, E:8, F:8, 0:80>>.

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
decode_option(125, Bin) ->
    {vivso, decode_vivso_list(Bin)};
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

decode_vivso_list(Bin) ->
    % Stub
    Bin.

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
%% 177 bus_id
decode_ipxe_suboption(16#b1, <<Type, Vendor:16, Device:16>>) ->
    {bus_id, {Type, Vendor, Device}};
%% 235 version
decode_ipxe_suboption(16#eb, <<Maj, Min, _/binary>>) ->
    {version, {Maj, Min}};
%% 189 san_drive (BIOS drive no.)
decode_ipxe_suboption(16#bd, <<Drive>>) ->
    {san_drive, Drive};
%% Boolean treatment ONLY for the feature-marker range 0x10-0x4f.
decode_ipxe_suboption(Tag, <<1>>) when Tag >= 16#10, Tag =< 16#4f ->
    {decode_ipxe_feature(Tag), true};
decode_ipxe_suboption(Tag, <<0>>) when Tag >= 16#10, Tag =< 16#4f ->
    {decode_ipxe_feature(Tag), false};
decode_ipxe_suboption(Tag, Value) ->
    {decode_ipxe_feature(Tag), Value}.

%% 16
decode_ipxe_feature(16#10) -> pxe_ext;
%% 17
decode_ipxe_feature(16#11) -> iscsi;
%% 18
decode_ipxe_feature(16#12) -> aoe;
%% 19
decode_ipxe_feature(16#13) -> http;
%% 20
decode_ipxe_feature(16#14) -> https;
%% 21
decode_ipxe_feature(16#15) -> tftp;
%% 22
decode_ipxe_feature(16#16) -> ftp;
%% 23
decode_ipxe_feature(16#17) -> dns;
%% 24
decode_ipxe_feature(16#18) -> bzimage;
%% 25
decode_ipxe_feature(16#19) -> multiboot;
%% 26
decode_ipxe_feature(16#1a) -> slam;
%% 27
decode_ipxe_feature(16#1b) -> srp;
%% 32
decode_ipxe_feature(16#20) -> nbi;
%% 33
decode_ipxe_feature(16#21) -> pxe;
%% 34
decode_ipxe_feature(16#22) -> elf;
%% 35
decode_ipxe_feature(16#23) -> comboot;
%% 36
decode_ipxe_feature(16#24) -> efi;
%% 37
decode_ipxe_feature(16#25) -> fcoe;
%% 38
decode_ipxe_feature(16#26) -> vlan;
%% 39
decode_ipxe_feature(16#27) -> menu;
%% 40
decode_ipxe_feature(16#28) -> sdi;
%% 41
decode_ipxe_feature(16#29) -> nfs;
decode_ipxe_feature(N) -> N.

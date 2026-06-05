-define(DHCP_MAGIC_COOKIE, 16#63825363).

-record(dhcp_message, {
    % Header
    op :: op(),
    htype :: htype(),
    hlen :: byte(),
    hops :: byte(),
    xid :: 0..16#FFFFFFFF,
    secs :: 0..16#FFFF,
    flags :: dhcp_flags(),

    % Addresses
    ciaddr :: inet:ip4_address(),
    yiaddr :: inet:ip4_address(),
    siaddr :: inet:ip4_address(),
    giaddr :: inet:ip4_address(),
    chaddr :: mac_address(),

    % Strings
    sname :: binary(),
    file :: binary(),

    % Options
    options :: [dhcp_option()]
}).
-type dhcp_message() :: #dhcp_message{}.

-type op() :: bootrequest | bootreply.
-type mac_address() :: {byte(), byte(), byte(), byte(), byte(), byte()}.
-type ib_mac_address() :: {
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte(),
    byte()
}.
-type dhcp_flags() :: [dhcp_flag()].
-type dhcp_flag() :: broadcast.
-type htype() ::
    reserved
    | ethernet
    | experimental_ethernet
    | ax25
    | proteon_pronet_token_ring
    | chaos
    | ieee802
    | arcnet
    | hyperchannel
    | lanstar
    | autonet_short_address
    | localtalk
    | localnet
    | ultra_link
    | smds
    | frame_relay
    | atm_16
    | hdlc
    | fibre_channel
    | atm_19
    | serial_line
    | atm_21
    | mil_std_188_220
    | metricom
    | ieee1394
    | mapos
    | twinaxial
    | eui64
    | hiparp
    | ip_arp_iso_7816_3
    | arpsec
    | ipsec_tunnel
    | infiniband
    | tia_102_p25_cai
    | wiegand_interface
    | pure_ip
    | hw_exp1
    | hfi
    | unified_bus
    | 0..255.

-type dhcp_option() ::
    {Tag :: 0..254, Value :: binary()}
    %% end option
    | {Tag :: 255}.

module Log =
  (val Logs.(
         src_log
         @@ Src.create ~doc:"Miragevpn library's configuration module"
              "ovpn.config")
      : Logs.LOG)

open Angstrom
module A = Angstrom

type inlineable =
  [ `Auth_user_pass
  | `Ca
  | `Connection
  | `Pkcs12
  | `Tls_auth of [ `Incoming | `Outgoing ] option
  | `Tls_cert
  | `Tls_key
  | `Secret
  | `Tls_crypt_v2 of bool ]

let string_of_inlineable = function
  | `Auth_user_pass -> "auth-user-pass"
  | `Ca -> "ca"
  | `Connection -> "connection"
  | `Pkcs12 -> "pkcs12"
  | `Tls_auth _ -> "tls-auth"
  | `Tls_cert -> "cert"
  | `Tls_key -> "key"
  | `Secret -> "secret"
  | `Tls_crypt_v2 _ -> "tls-crypt-v2"

type inline_or_path =
  [ `Need_inline of inlineable | `Path of string * inlineable ]

let int_of_ping_interval = function
  | `Not_configured -> 0
  | `Seconds 0 ->
      failwith
        "Miragevpn.Config, internal invariant Ping_interval `Seconds <> 0 \
         violated"
  | `Seconds n -> n

let ( (cipher_to_cs : string -> Tls.Ciphersuite.ciphersuite),
      (cs_to_cipher : Tls.Ciphersuite.ciphersuite -> string) ) =
  let map =
    [
      ( "TLS-ECDHE-ECDSA-WITH-AES-256-GCM-SHA384",
        `ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 );
      ( "TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384",
        `ECDHE_RSA_WITH_AES_256_GCM_SHA384 );
      ("TLS-DHE-RSA-WITH-AES-256-GCM-SHA384", `DHE_RSA_WITH_AES_256_GCM_SHA384);
      ( "TLS-ECDHE-ECDSA-WITH-CHACHA20-POLY1305-SHA256",
        `ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256 );
      ( "TLS-ECDHE-RSA-WITH-CHACHA20-POLY1305-SHA256",
        `ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 );
      ( "TLS-DHE-RSA-WITH-CHACHA20-POLY1305-SHA256",
        `DHE_RSA_WITH_CHACHA20_POLY1305_SHA256 );
      ( "TLS-ECDHE-ECDSA-WITH-AES-128-GCM-SHA256",
        `ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 );
      ( "TLS-ECDHE-RSA-WITH-AES-128-GCM-SHA256",
        `ECDHE_RSA_WITH_AES_128_GCM_SHA256 );
      ("TLS-DHE-RSA-WITH-AES-128-GCM-SHA256", `DHE_RSA_WITH_AES_128_GCM_SHA256);
      ( "TLS-ECDHE-ECDSA-WITH-AES-256-CBC-SHA384",
        `ECDHE_ECDSA_WITH_AES_256_CBC_SHA384 );
      ( "TLS-ECDHE-RSA-WITH-AES-256-CBC-SHA384",
        `ECDHE_RSA_WITH_AES_256_CBC_SHA384 );
      ("TLS-DHE-RSA-WITH-AES-256-CBC-SHA256", `DHE_RSA_WITH_AES_256_CBC_SHA256);
      ( "TLS-ECDHE-ECDSA-WITH-AES-128-CBC-SHA256",
        `ECDHE_ECDSA_WITH_AES_128_CBC_SHA256 );
      ( "TLS-ECDHE-RSA-WITH-AES-128-CBC-SHA256",
        `ECDHE_RSA_WITH_AES_128_CBC_SHA256 );
      ("TLS-DHE-RSA-WITH-AES-128-CBC-SHA256", `DHE_RSA_WITH_AES_128_CBC_SHA256);
      ("TLS-ECDHE-ECDSA-WITH-AES-256-CBC-SHA", `ECDHE_ECDSA_WITH_AES_256_CBC_SHA);
      ("TLS-ECDHE-RSA-WITH-AES-256-CBC-SHA", `ECDHE_RSA_WITH_AES_256_CBC_SHA);
      ("TLS-DHE-RSA-WITH-AES-256-CBC-SHA", `DHE_RSA_WITH_AES_256_CBC_SHA);
      ("TLS-ECDHE-ECDSA-WITH-AES-128-CBC-SHA", `ECDHE_ECDSA_WITH_AES_128_CBC_SHA);
      ("TLS-ECDHE-RSA-WITH-AES-128-CBC-SHA", `ECDHE_RSA_WITH_AES_128_CBC_SHA);
      ("TLS-DHE-RSA-WITH-AES-128-CBC-SHA", `DHE_RSA_WITH_AES_128_CBC_SHA);
    ]
  in
  let rev_map = List.map (fun (a, b) -> (b, a)) map in
  ( (fun s ->
      match List.assoc_opt s map with
      | None -> failwith ("unsupported tls-cipher " ^ s)
      | Some c -> c),
    fun c -> List.assoc c rev_map )

let ( (cipher13_to_cs13 : string -> Tls.Ciphersuite.ciphersuite13),
      (cs13_to_cipher13 : Tls.Ciphersuite.ciphersuite13 -> string) ) =
  let map =
    [
      ("TLS_AES_256_GCM_SHA384", `AES_256_GCM_SHA384);
      ("TLS_CHACHA20_POLY1305_SHA256", `CHACHA20_POLY1305_SHA256);
      ("TLS_AES_128_GCM_SHA256", `AES_128_GCM_SHA256);
    ]
  in
  let rev_map = List.map (fun (a, b) -> (b, a)) map in
  ( (fun s ->
      match List.assoc_opt s map with
      | None -> failwith ("unsupported tls-ciphersuite " ^ s)
      | Some c -> c),
    fun c -> List.assoc c rev_map )

module Conf_map = struct
  type flag = unit

  (* Checklist when adding a new entry here:
     - This file:
        - Defaults.common
            Declare default value as per `man openvpn`, if any.
        - Conf_map.pp_b:
           Enable config-serialization of the values
           (must be in the format from `man openvpn`)
        - a_config_entry:
           Expose it to the parser
     - Miragevpn.mli:Config 'a k:
         Expose it in the mli interface.
         Must add a docstring comment detailing which config entry the
         key corresponds to, and its semantics if there can be any doubt.
     - README.md:
         - Document the existence of this option
         - Remove it from Ignored Directives and/or Unimplemented Directives
  *)
  type 'a k =
    | Auth_nocache : flag k
    | Auth_retry : [ `Interact | `Nointeract | `None ] k
    | Auth_user_pass : (string * string) k
    | Auth_user_pass_verify : (string * [ `Via_env | `Via_file ]) k
    | Bind
        : (int option
          * [ `Domain of [ `host ] Domain_name.t | `Ip of Ipaddr.t ] option)
          option
          k
    | Ca : X509.Certificate.t list k
    | Cipher : string k
    | Comp_lzo : flag k
    | Connect_retry : (int * int) k
    | Connect_retry_max : [ `Unlimited | `Times of int ] k
    | Connect_timeout : int k
    | Dev : ([ `Tun | `Tap ] * string option) k
    | Dhcp_disable_nbt : flag k
    | Dhcp_dns : Ipaddr.t list k
    | Dhcp_ntp : Ipaddr.t list k
    | Dhcp_domain : [ `host ] Domain_name.t k
    | Float : flag k
    | Handshake_window : int k
    | Ifconfig : (Ipaddr.t * Ipaddr.t) k
    | Ifconfig_nowarn : flag k
    | Link_mtu : int k
    | Mssfix : int k
    | Mute_replay_warnings : flag k
    | Passtos : flag k
    | Persist_key : flag k
    | Persist_tun : flag k
    | Ping_interval : [ `Not_configured | `Seconds of int ] k
    | Ping_timeout : [ `Restart of int | `Exit of int ] k
    | Port : int k
    | Pull : flag k
    | Proto
        : ([ `Ipv6 | `Ipv4 ] option
          * [ `Udp | `Tcp of [ `Server | `Client ] option ])
          k
      (* see socket.c:static const struct proto_names proto_names[] *)
    | Remote
        : ([ `Domain of [ `host ] Domain_name.t * [ `Ipv4 | `Ipv6 | `Any ]
           | `Ip of Ipaddr.t ]
          * int
          * [ `Udp | `Tcp ])
          list
          k
    | Remote_cert_tls : [ `Server | `Client ] k
    | Remote_random : flag k
    | Renegotiate_bytes : int k
    | Renegotiate_packets : int k
    | Renegotiate_seconds : int k
    | Replay_window : (int * int) k
    | Resolv_retry : [ `Infinite | `Seconds of int ] k
    | Route
        : ([ `Ip of Ipaddr.t | `Net_gateway | `Remote_host | `Vpn_gateway ]
          * Ipaddr.Prefix.t option
          * [ `Ip of Ipaddr.t | `Net_gateway | `Remote_host | `Vpn_gateway ]
            option
          * [ `Default | `Metric of int ])
          list
          k
    | Route_delay : (int * int) k
    | Route_gateway : [ `Ip of Ipaddr.t | `Default | `Dhcp ] k
    | Route_metric : [ `Default | `Metric of int ] k
    | Route_nopull : flag k
    | Script_security : int k
    | Secret : (Cstruct.t * Cstruct.t * Cstruct.t * Cstruct.t) k
    | Server : Ipaddr.V4.Prefix.t k
    | Tls_auth
        : ([ `Incoming | `Outgoing ] option
          * Cstruct.t
          * Cstruct.t
          * Cstruct.t
          * Cstruct.t)
          k
    | Tls_cert : X509.Certificate.t k
    | Tls_mode : [ `Client | `Server ] k
    | Tls_key : X509.Private_key.t k
    | Tls_timeout : int k
    | Tls_version_min : (Tls.Core.tls_version * bool) k
    | Tls_version_max : Tls.Core.tls_version k
    | Tls_cipher : Tls.Ciphersuite.ciphersuite list k
    | Tls_ciphersuite : Tls.Ciphersuite.ciphersuite13 list k
    | Tls_crypt_v2_client
        : ((Cstruct.t * Cstruct.t * Cstruct.t * Cstruct.t) * Cstruct.t * bool) k
    | Tls_crypt_v2_server : ((Cstruct.t * Cstruct.t) * bool) k
    | Topology : [ `Net30 | `P2p | `Subnet ] k
    | Transition_window : int k
    | Tun_mtu : int k
    | Verb : int k
    | Verify_client_cert : [ `None | `Optional | `Required ] k
    | Verify_x509_name : [ `host ] Domain_name.t k

  module K = struct
    type 'a t = 'a k

    let compare : type a b. a t -> b t -> (a, b) Gmap.Order.t =
     fun a b ->
      (* ensure they're plain variant tags: *)
      let is_int x = Obj.(magic x |> is_int) in
      assert (is_int a && is_int b);
      match compare (Obj.magic a : int) (Obj.magic b) with
      | 0 -> Obj.magic Gmap.Order.Eq (* GADT equality :-/ *)
      | x when x < 0 -> Lt
      | _ -> Gt
  end

  include Gmap.Make (K)

  let is_valid_config t =
    let ensure_mem k err = if mem k t then Ok () else Error err in
    (* let ensure_not k err = if not (mem k t) then Ok () else Error err in *)
    let open Result.Infix in
    Result.map_error
      (fun err -> `Msg ("not a valid config: " ^ err))
      ( ensure_mem Cipher "config must specify 'cipher AES-256-CBC'"
      >>= fun () ->
        if mem Cipher t && get Cipher t <> "AES-256-CBC" then
          Error "currently only supported Cipher is 'AES-256-CBC'"
        else Ok () )

  let is_valid_server_config t =
    let ensure_mem k err = if mem k t then Ok () else Error err in
    let open Result.Infix in
    is_valid_config t >>= fun () ->
    Result.map_error
      (fun err -> `Msg ("not a valid server config: " ^ err))
      ( ensure_mem Bind "does not have a bind" >>= fun () ->
        (match find Tls_mode t with
        | None | Some `Client -> Error "config must specify 'tls-server'"
        | Some `Server -> Ok ())
        >>= fun () ->
        match (find Tls_cert t, find Tls_key t) with
        | Some _, Some _ -> Ok ()
        | None, None -> Error "missing tls-cert and tls-key"
        | Some _, None -> Error "missing tls-cert"
        | None, Some _ -> Error "missing tls-key" (* ^-- TODO or has -pkcs12 *)
      )

  let is_valid_client_config t =
    let open Result.Infix in
    let ensure_mem k err = if mem k t then Ok () else Error err in
    let ensure_not k err = if not (mem k t) then Ok () else Error err in
    is_valid_config t >>= fun () ->
    Result.map_error
      (fun err -> `Msg ("not a valid client config: " ^ err))
      ( ensure_mem Remote "does not have a remote" >>= fun () ->
        let _todo = ensure_not in
        (match (find Tls_mode t, find Secret t) with
        | None, None | Some `Server, _ ->
            Error "is a TLS server, not a TLS client"
        | None, Some _ ->
            Log.warn (fun m -> m "using non-forward secure static key mode");
            Ok ()
        | Some _, Some _ -> Error "both static secret and TLS mode specified"
        | Some `Client, None -> (
            match (find Auth_user_pass t, find Tls_cert t, find Tls_key t) with
            | _, Some _, None -> Error "tls-cert provided, but no tls-key"
            | _, None, Some _ -> Error "tls-key provided, but not tls-cert"
            | Some _, None, None -> Ok ()
            | _, Some cert, Some key ->
                let cert_pubkey = X509.Certificate.public_key cert in
                let key_pubkey = X509.Private_key.public key in
                if
                  Cstruct.equal
                    (X509.Public_key.fingerprint cert_pubkey)
                    (X509.Public_key.fingerprint key_pubkey)
                then Ok ()
                else Error "key and cert do not match"
            | None, None, None ->
                Error
                  "config has neither user/password, nor TLS client certificate"
                (* ^-- TODO or has -pkcs12 *)))
        >>= fun () ->
        (if mem Remote_cert_tls t && get Remote_cert_tls t <> `Server then
           Error "remote-cert-tls is not SERVER?!"
         else Ok ())
        >>= fun () ->
        ensure_not Tls_crypt_v2_server
          "server tls-crypt-v2 key passed in tls-crypt-v2" )

  let pp_key ppf (a, b, c, d) =
    Fmt.pf ppf
      "-----BEGIN OpenVPN Static key V1-----\n\
       %a\n\
       -----END OpenVPN Static key V1-----"
      Fmt.(array ~sep:(any "\n") string)
      (match Cstruct.concat [ a; b; c; d ] |> Hex.of_cstruct with
      | `Hex h -> Array.init (256 / 16) (fun i -> String.sub h (i * 32) 32))

  let rec pp_pem_b64 ppf cs =
    let len = Cstruct.length cs in
    if len = 0 then Fmt.pf ppf ""
    else
      let len = min len 48 in
      let () =
        Fmt.pf ppf "%s\n" (Base64.encode_string (Cstruct.to_string ~len cs))
      in
      pp_pem_b64 ppf (Cstruct.shift cs len)

  let pp_tls_crypt_v2_client ppf ((a, b, c, d), wkc) =
    Fmt.pf ppf
      "-----BEGIN OpenVPN tls-crypt-v2 client key-----\n\
       %a-----END OpenVPN tls-crypt-v2 client key-----" pp_pem_b64
      (Cstruct.concat [ a; b; c; d; wkc ])

  let pp_tls_crypt_v2_server ppf (a, b) =
    Fmt.pf ppf
      "-----BEGIN OpenVPN tls-crypt-v2 server key-----\n\
       %a-----END OpenVPN tls-crypt-v2 server key-----" pp_pem_b64
      (Cstruct.concat [ a; b ])

  let pp_b ?(sep = Fmt.any "@.") ppf (b : b) =
    let p () = Fmt.pf ppf in
    let (B (k, v)) = b in
    let pp_x509 ppf cert =
      Fmt.pf ppf
        "# CN: %S\n\
         # Expiry: %a\n\
         # Hosts: %a\n\
         # Cert fingerprint (sha256): %a\n\
         # Key fingerprint (sha256): %a\n\
         %s"
        (match
           X509.(Distinguished_name.common_name (Certificate.subject cert))
         with
        | None -> "NO common name"
        | Some x -> x)
        Fmt.(pair ~sep:(any " -> ") Ptime.(pp_human ()) Ptime.(pp_human ()))
        (X509.Certificate.validity cert)
        X509.Host.Set.pp
        (X509.Certificate.hostnames cert)
        Hex.pp
        (Hex.of_cstruct (X509.Certificate.fingerprint `SHA256 cert))
        Hex.pp
        (Hex.of_cstruct
           (X509.Public_key.fingerprint ~hash:`SHA256
              (X509.Certificate.public_key cert)))
        (X509.Certificate.encode_pem cert |> Cstruct.to_string)
    in
    let pp_cert cert = p () "cert [inline]\n<cert>\n%a</cert>" pp_x509 cert in
    let pp_ca certs =
      p () "ca [inline]\n<ca>\n%a</ca>" Fmt.(list ~sep:(any "\n") pp_x509) certs
    in
    let pp_x509_private_key key =
      p () "key [inline]\n<key>\n%s</key>"
        (X509.Private_key.encode_pem key |> Cstruct.to_string)
    in
    let pp_tls_version ppf v =
      Fmt.string ppf
        (match v with
        | `TLS_1_3 -> "1.3"
        | `TLS_1_2 -> "1.2"
        | `TLS_1_1 -> "1.1"
        | `TLS_1_0 -> "1.0")
    in
    match (k, v) with
    | Auth_nocache, () -> p () "auth-nocache"
    | Auth_retry, `None -> p () "auth-retry none"
    | Auth_retry, `Nointeract -> p () "auth-retry nointeract"
    | Auth_retry, `Interact -> p () "auth-retry interact"
    | Auth_user_pass, (user, pass) ->
        p ()
          "auth-user-pass [inline]\n<auth-user-pass>\n%s\n%s\n</auth-user-pass>"
          user pass
    | Auth_user_pass_verify, (cmd, mode) ->
        p () "auth-user-pass-verify %s %s" cmd
          (match mode with `Via_file -> "via-file" | `Via_env -> "via-env")
    | Bind, None -> p () "nobind"
    | Bind, Some opts -> (
        p () "bind";
        (match fst opts with
        | Some port -> p () "%alport %d" sep () port
        | None -> ());
        match snd opts with
        | None -> ()
        | Some (`Domain n) -> p () "%alocal %a" sep () Domain_name.pp n
        | Some (`Ip ip) -> p () "%alocal %a" sep () Ipaddr.pp ip)
    | Ca, ca -> pp_ca ca
    | Cipher, cipher -> p () "cipher %s" cipher
    | Comp_lzo, () -> p () "comp-lzo"
    | Connect_retry, (low, high) -> p () "connect-retry %d %d" low high
    | Connect_retry_max, `Unlimited -> p () "connect-retry-max unlimited"
    | Connect_retry_max, `Times i -> p () "connect-retry-max %d" i
    | Connect_timeout, seconds -> p () "connect-timeout %d" seconds
    | Dev, (`Tap, None) -> p () "dev tap"
    | Dev, (`Tun, None) -> p () "dev tun"
    | Dev, (typ, Some name) ->
        p () "dev %s%adev-type %s" name sep ()
          (match typ with `Tun -> "tun" | `Tap -> "tap")
    | Dhcp_disable_nbt, () -> p () "dhcp-option disable-nbt"
    | Dhcp_domain, n -> p () "dhcp-option domain %a" Domain_name.pp n
    | Dhcp_ntp, ips ->
        Fmt.(list ~sep @@ fun ppf -> pf ppf "dhcp-option ntp %a" Ipaddr.pp)
          ppf ips
    | Dhcp_dns, ips ->
        Fmt.(list ~sep @@ fun ppf -> pf ppf "dhcp-option dns %a" Ipaddr.pp)
          ppf ips
    | Float, () -> p () "float"
    | Handshake_window, seconds -> p () "hand-window %d" seconds
    | Ifconfig, (local, remote) ->
        p () "ifconfig %a %a" Ipaddr.pp local Ipaddr.pp remote
    | Ifconfig_nowarn, () -> p () "ifconfig-nowarn"
    | Link_mtu, i -> p () "link-mtu %d" i
    | Ping_interval, n -> p () "ping %d" (int_of_ping_interval n)
    | Ping_timeout, `Exit timeout -> p () "ping-exit %d" timeout
    | Ping_timeout, `Restart timeout -> p () "ping-restart %d" timeout
    | Mssfix, int -> p () "mssfix %d" int
    | Mute_replay_warnings, () -> p () "mute-replay-warnings"
    | Passtos, () -> p () "passtos"
    | Persist_key, () -> p () "persist-key"
    | Persist_tun, () -> p () "persist-tun"
    | Port, port -> p () "port %u" port
    | Proto, (ip_v, kind) ->
        p () "proto %s%s%s"
          (match kind with `Udp -> "udp" | `Tcp _ -> "tcp")
          (match ip_v with Some `Ipv4 -> "4" | Some `Ipv6 -> "6" | None -> "")
          (match kind with
          | `Tcp (Some `Client) -> "-client"
          | `Tcp (Some `Server) -> "-server"
          | `Tcp None | `Udp -> "")
    | Pull, () -> p () "pull"
    | Remote, lst ->
        p () "%a"
          Fmt.(
            list ~sep @@ fun ppf (endp, port, proto) ->
            let pp_endpoint, ip_proto =
              match endp with
              | `Domain (name, prot) ->
                  ( (fun ppf () -> Domain_name.pp ppf name),
                    match prot with `Ipv4 -> "4" | `Ipv6 -> "6" | `Any -> "" )
              | `Ip ip ->
                  ( (fun ppf () -> Ipaddr.pp ppf ip),
                    match ip with V4 _ -> "4" | V6 _ -> "6" )
            in
            pf ppf "remote %a %d %s%s" pp_endpoint () port
              (match proto with `Udp -> "udp" | `Tcp -> "tcp")
              ip_proto)
          lst
    | Remote_cert_tls, `Server -> p () "remote-cert-tls server"
    | Remote_cert_tls, `Client -> p () "remote-cert-tls client"
    | Remote_random, () -> p () "remote-random"
    | Renegotiate_bytes, i -> p () "reneg-bytes %d" i
    | Renegotiate_packets, i -> p () "reneg-pkts %d" i
    | Renegotiate_seconds, i -> p () "reneg-sec %d" i
    | Replay_window, (low, high) -> p () "replay-window %d %d" low high
    | Resolv_retry, `Infinite -> p () "resolv-retry infinite"
    | Resolv_retry, `Seconds i -> p () "resolv-retry %d" i
    | Route, routes ->
        routes
        |> List.iter (fun (network, netmask, gateway, metric) ->
               let pp_addr ppf v =
                 Fmt.pf ppf "%s"
                   (match v with
                   | `Ip ip -> Ipaddr.to_string ip
                   | `Net_gateway -> "net_gateway"
                   | `Remote_host -> "remote_host"
                   | `Vpn_gateway -> "vpn_gateway")
               in
               p () "route %a %a %a %s" pp_addr network
                 Fmt.(option ~none:(any "default") Ipaddr.Prefix.pp)
                 netmask
                 Fmt.(option ~none:(any "default") pp_addr)
                 gateway
                 (match metric with
                 | `Default -> "default"
                 | `Metric i -> string_of_int i))
    | Route_delay, (n, w) -> p () "route-delay %d %d" n w
    | Route_gateway, `Default -> p () "route-gateway default"
    | Route_gateway, `Dhcp -> p () "route-gateway dhcp"
    | Route_gateway, `Ip ip -> p () "route-gateway %a" Ipaddr.pp ip
    | Route_nopull, () -> p () "route-nopull"
    | Script_security, d -> p () "script-security %u" d
    | Secret, (a, b, c, d) -> p () "<secret>\n%a\n</secret>" pp_key (a, b, c, d)
    | Server, cidr ->
        p () "server %a %a" Ipaddr.V4.pp
          (Ipaddr.V4.Prefix.address cidr)
          Ipaddr.V4.pp
          (Ipaddr.V4.Prefix.netmask cidr)
    | Tls_auth, (direction, a, b, c, d) ->
        p () "tls-auth [inline]%s\n<tls-auth>\n%a\n</tls-auth>"
          (match direction with
          | Some `Incoming -> " 1"
          | Some `Outgoing -> " 0"
          | None -> "")
          pp_key (a, b, c, d)
    | Route_metric, `Metric i -> p () "route-metric %d" i
    | Route_metric, `Default -> p () "route-metric default"
    | Tls_cert, cert -> pp_cert cert
    | Tls_key, key -> pp_x509_private_key key
    | Tls_version_min, (ver, or_highest) ->
        p () "tls-version-min %a%s" pp_tls_version ver
          (if or_highest then " or-highest" else "")
    | Tls_version_max, ver -> p () "tls-version-max %a" pp_tls_version ver
    | Tls_mode, `Server -> p () "tls-server"
    | Tls_mode, `Client -> p () "tls-client"
    | Tls_timeout, seconds -> p () "tls-timeout %d" seconds
    | Tls_cipher, ciphers ->
        p () "tls-cipher %a"
          Fmt.(list ~sep:(any ":") string)
          (List.map cs_to_cipher ciphers)
    | Tls_ciphersuite, ciphers ->
        p () "tls-ciphersuite %a"
          Fmt.(list ~sep:(any ":") string)
          (List.map cs13_to_cipher13 ciphers)
    | Tls_crypt_v2_client, (key, wkc, force_cookie) ->
        p () "tls-crypt-v2 [inline] %s\n<tls-crypt-v2>\n%a\n</tls-crypt-v2>"
          (if force_cookie then "force-cookie" else "allow-noncookie")
          pp_tls_crypt_v2_client (key, wkc)
    | Tls_crypt_v2_server, (key, force_cookie) ->
        p () "tls-crypt-v2 [inline] %s<tls-crypt-v2>\n%a\n</tls-crypt-v2>"
          (if force_cookie then "force-cookie" else "allow-noncookie")
          pp_tls_crypt_v2_server key
    | Topology, v ->
        p () "topology %s"
          (match v with
          | `Net30 -> "net30"
          | `P2p -> "p2p"
          | `Subnet -> "subnet")
    | Transition_window, seconds -> p () "tran-window %d" seconds
    | Tun_mtu, int -> p () "tun-mtu %d" int
    | Verb, int -> p () "verb %d" int
    | Verify_client_cert, mode ->
        p () "verify-client-cert %s"
          (match mode with
          | `None -> "none"
          | `Optional -> "optional"
          | `Required -> "require")
    | Verify_x509_name, host ->
        p () "verify-x509-name %a name" Domain_name.pp host

  let pp_with_sep ?(sep = Fmt.any "@.") ppf t =
    let minimized_t =
      if find Tls_mode t = Some `Client && mem Pull t then (
        Fmt.pf ppf "client%a" sep ();
        remove Tls_mode t |> remove Pull)
      else t
    in
    Fmt.(pf ppf "%a" (list ~sep pp_b) (bindings minimized_t))

  let pp ppf t = pp_with_sep ppf t
end

module Defaults = struct
  let common =
    let open Conf_map in
    empty
    |> add Ping_interval `Not_configured
    |> add Ping_timeout (`Restart 120)
    |> add Renegotiate_seconds 3600
    |> add Handshake_window 60 |> add Transition_window 3600
    |> add Proto (None, `Udp)

  let client =
    let open Conf_map in
    common |> add Tls_timeout 2
    |> add Bind (Some (None, None))
    |> add Resolv_retry `Infinite |> add Auth_retry `None
    |> add Connect_timeout 120
    |> add Connect_retry_max `Unlimited

  let server =
    let open Conf_map in
    common |> add Bind (Some (Some 1194, None))
end

open Conf_map

type line =
  [ `Entries of b list
  | `Entry of b
  | `Comment of string
  | `Ignored of string
  | `Inline of string * string
  | `Keepalive of int * int (* interval * timeout *)
  | `Remote of
    [ `Domain of [ `host ] Domain_name.t * [ `Ipv6 | `Ipv4 | `Any ]
    | `Ip of Ipaddr.t ]
    * [ `Port of int | `Default_rport ]
    * [ `Udp | `Tcp ] option
  | `Rport of int (* remote port number used by --remote option *)
  | `Proto_force of [ `Tcp | `Udp ]
  | `Socks_proxy of string * int * [ `Inline | `Path of string ]
  | inline_or_path
  | `Dev of string (* [dev name] stanza requiring a [dev-type]*)
  | `Dev_type of [ `Tun | `Tap ] (* [dev-type] stanza requiring [dev name]*) ]

let pp_line ppf (x : line) =
  let v = Fmt.pf in
  match x with
  | `Remote (host, port, proto) ->
      let pphost ppf () =
        match host with
        | `Domain (dom, _proto) -> Domain_name.pp ppf dom
        | `Ip ip -> Ipaddr.pp ppf ip
      in
      v ppf "(remote %a, %s, %s)" pphost ()
        (match port with
        | `Default_rport -> "default"
        | `Port i -> string_of_int i)
        (match proto with
        | None -> "any"
        | Some `Tcp -> "tcp"
        | Some `Udp -> "udp")
  | `Entries bs -> v ppf "entries: @[<v>%a@]" Fmt.(list ~sep:(any "@,") pp_b) bs
  | `Entry b -> v ppf "entry: %a" (fun v -> pp_b v) b
  | `Comment s -> v ppf "# %s" s
  | `Ignored s -> v ppf "# IGNORED: %s" s
  | `Keepalive (interval, timeout) -> v ppf "keepalive %d %d" interval timeout
  | `Rport d -> v ppf "rport %d" d
  | `Proto_force `Tcp -> v ppf "proto-force tcp"
  | `Proto_force `Udp -> v ppf "proto-force udp"
  | `Socks_proxy _ -> v ppf "socks-proxy"
  | `Inline (tag, content) -> v ppf "<%s>:%S" tag content
  | `Path (fn, _) -> v ppf "inline-or-path: %s" fn
  | `Need_inline _ -> v ppf "inline-or-path: Need_inline"
  | `Dev name -> v ppf "dev %S" name
  | `Dev_type `Tun -> v ppf "dev-type tun"
  | `Dev_type `Tap -> v ppf "dev-type tap"

let a_comment =
  (* MUST have # or ; at the first column of a line. *)
  (char '#' <|> char ';')
  *> skip_many (skip @@ function '\n' -> false | _ -> true)

let a_newline = choice [ string "\r\n" *> return (); char '\n' *> return () ]
let a_whitespace_unit = skip (function ' ' | '\t' -> true | _ -> false)

let a_single_param =
  (* Handles single-quoted or double-quoted, using backslash as escaping char.*)
  let rec escaped q acc : string Angstrom.t =
    let again = escaped q in
    let ret acc = return (String.concat "" (List.rev acc)) in
    peek_char >>= function
    | Some '\\' -> (
        advance 1 >>= fun () ->
        any_char >>= function
        | q2 when q = q2 -> again (String.make 1 q :: acc)
        | c -> again (String.make 1 c :: "\\" :: acc))
    | Some q2 when q = q2 -> ret acc
    | Some c -> advance 1 >>= fun () -> again (String.make 1 c :: acc)
    | None ->
        fail
          ("end of input while looking for matching " ^ String.make 1 q
         ^ " quote")
  in
  choice
    [
      char '\'' *> Angstrom.commit *> escaped '\'' [] <* char '\'';
      char '"' *> Angstrom.commit *> escaped '"' [] <* char '"';
      ( take_while (function
          | ' ' | '\t' | '\'' | '"' | '\n' -> false
          | _ -> true)
      >>= fun v ->
        if
          String.(contains_from v (min 0 @@ length v) '\'')
          || String.(contains_from v (min 0 @@ length v) '"')
        then fail "unquoted parameter contains quote"
        else return v );
    ]

let a_whitespace_or_comment = a_comment <|> a_whitespace_unit
let a_ign_whitespace = skip_many a_whitespace_or_comment
let a_ign_whitespace_no_comment = skip_many a_whitespace_unit
let a_whitespace = skip_many1 a_whitespace_or_comment
let not_control_char = function '\x00' .. '\x1f' | '\x7f' -> false | _ -> true
let a_line predicate = take_while predicate <* (end_of_line <|> end_of_input)

let a_number =
  take_while1 (function '0' .. '9' -> true | _ -> false) >>= fun str ->
  match int_of_string str with
  | i when string_of_int i = str -> return i
  | _ -> fail (Fmt.str "Invalid number: %S" str)
  | exception _ -> fail (Fmt.str "Invalid number: %S" str)

let a_number_range min' max' =
  a_number >>= function
  | n when n <= max' && min' <= n -> return n
  | n -> fail (Fmt.str "Number out of range: %d" n)

let a_client =
  (* alias for --tls-client --pull *)
  string "client" *> a_ign_whitespace
  *> return (`Entries [ B (Tls_mode, `Client); B (Pull, ()) ])

let a_dev =
  let a_device_name =
    choice
      [
        ( string "tun" *> a_line not_control_char >>| fun x ->
          let name =
            let x = String.trim x in
            if x = "" then None else Some ("tun" ^ x)
          in
          (Some `Tun, name) );
        ( string "tap" *> a_line not_control_char >>| fun x ->
          let name =
            let x = String.trim x in
            if x = "" then None else Some ("tap" ^ x)
          in
          (Some `Tap, name) );
        (a_single_param >>| fun name -> (None, Some name));
      ]
  in
  string "dev" *> a_whitespace *> a_device_name >>| function
  | Some typ, name -> `Entry (B (Dev, (typ, name)))
  | None, Some name -> `Dev name
  | None, None ->
      failwith
        "config dev stanza with no name or type; this is a bug in the config \
         parser"

let a_dev_type =
  (* this is used to specify the type of a [dev] stanza
     giving a custom name from which the type cannot be inferred *)
  string "dev-type" *> a_whitespace
  *> choice [ string "tun" *> return `Tun; string "tap" *> return `Tap ]
  >>| fun typ -> `Dev_type typ

let a_proto =
  string "proto" *> a_whitespace
  *> choice
       [
         string "tcp6-client" *> return (Some `Ipv6, `Tcp (Some `Client));
         string "tcp6-server" *> return (Some `Ipv6, `Tcp (Some `Server));
         string "tcp6" *> return (Some `Ipv6, `Tcp None);
         string "tcp4-client" *> return (Some `Ipv4, `Tcp (Some `Client));
         string "tcp4-server" *> return (Some `Ipv4, `Tcp (Some `Server));
         string "tcp-client" *> return (None, `Tcp (Some `Client));
         string "tcp-server" *> return (None, `Tcp (Some `Server));
         string "tcp4" *> return (Some `Ipv4, `Tcp None);
         string "tcp" *> return (None, `Tcp None);
         string "udp6" *> return (Some `Ipv6, `Udp);
         string "udp4" *> return (Some `Ipv4, `Udp);
         string "udp" *> return (None, `Udp);
       ]
  >>| fun prot -> `Entry (B (Proto, prot))

let a_proto_force =
  string "proto-force" *> a_whitespace
  *> choice [ string "tcp" *> return `Tcp; string "udp" *> return `Udp ]
  >>| fun prot -> `Proto_force prot

let a_resolv_retry =
  string "resolv-retry" *> a_whitespace
  *> choice
       [
         string "infinite" *> return `Infinite;
         (a_number >>= fun i -> return (`Seconds i));
       ]
  >>| fun i -> `Entry (B (Resolv_retry, i))

let a_filepath kind =
  choice
    [
      string "[inline]" *> return (`Need_inline kind);
      (a_single_param >>| fun p -> `Path (p, kind));
    ]

let a_option_with_single_path name kind =
  string name *> a_whitespace *> a_filepath kind

let a_ca = a_option_with_single_path "ca" `Ca

let a_ca_payload str =
  match X509.Certificate.decode_pem_multiple (Cstruct.of_string str) with
  | Ok certs -> Ok (B (Ca, certs))
  | Error (`Msg msg) -> Error (Fmt.str "ca: invalid certificate(s): %s" msg)

let a_cert = a_option_with_single_path "cert" `Tls_cert

let a_cert_payload str =
  match X509.Certificate.decode_pem (Cstruct.of_string str) with
  | Ok cert -> Ok (B (Tls_cert, cert))
  | Error (`Msg msg) -> Error (Fmt.str "cert: invalid certificate: %s" msg)

let a_key = a_option_with_single_path "key" `Tls_key

let a_key_payload str =
  match X509.Private_key.decode_pem (Cstruct.of_string str) with
  | Ok key -> Ok (B (Tls_key, key))
  | Error (`Msg msg) -> Error ("no key found in x509 tls-key: " ^ msg)

let a_pkcs12 = a_option_with_single_path "pkcs12" `Pkcs12

let a_tls_auth =
  a_option_with_single_path "tls-auth" () >>= fun source ->
  (* --key-direction or the optional arg here:
     0 -> CN_OUTGOING
     1 -> CN_INCOMING
  *)
  choice
    [
      a_whitespace *> string "0" *> return (Some `Outgoing);
      a_whitespace *> string "1" *> return (Some `Incoming);
      return None;
    ]
  >>| fun direction ->
  match source with
  | `Need_inline () -> `Need_inline (`Tls_auth direction)
  | `Path (path, ()) -> `Path (path, `Tls_auth direction)

let a_tls_crypt_v2 =
  string "tls-crypt-v2" *> a_whitespace *> a_filepath () >>= fun source ->
  choice
    [
      a_whitespace *> string "force-cookie" *> return true;
      a_whitespace *> string "allow-noncookie" *> return false;
      return false;
      (* default is allow-noncookie *)
    ]
  >>| fun force_cookie ->
  match source with
  | `Need_inline () -> `Need_inline (`Tls_crypt_v2 force_cookie)
  | `Path (path, ()) -> `Path (path, `Tls_crypt_v2 force_cookie)

let tls_crypt_v2_client_pem_name = "OpenVPN tls-crypt-v2 client key"
let tls_crypt_v2_server_pem_name = "OpenVPN tls-crypt-v2 server key"

let inline_pem_payload pem_name element =
  Angstrom.skip_many (a_whitespace_or_comment *> end_of_line)
  *> (string ("-----BEGIN " ^ pem_name ^ "-----") *> a_newline <|> fail "FIXME")
  *> many_till
       (take_while (function
          | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '+' | '/' | '=' -> true
          | _ -> false)
       <* (end_of_line <|> fail "Invalid base64 character"))
       (string ("-----END " ^ pem_name ^ "-----") *> a_newline
       <|> fail "Missing END mark")
  <* commit
  <* (skip_many (a_newline <|> a_whitespace) *> end_of_input
     <|> ( pos >>= fun i ->
           Fmt.kstr fail "Data after -----END mark at byte offset %d" i ))
  >>= fun lst ->
  let s = String.concat "" lst in
  match Base64.decode s with
  | Ok s -> return (Cstruct.of_string s)
  | Error (`Msg e) -> Fmt.kstr fail "Bad base64 in %s pem: %s" element e

let inline_payload element =
  let abort s = fail ("Invalid " ^ element ^ " HMAC key: " ^ s) in
  Angstrom.skip_many (a_whitespace_or_comment *> end_of_line)
  *> (string "-----BEGIN OpenVPN Static key V1-----" *> a_newline
     <|> abort "Missing Static key V1 -----BEGIN mark")
  *> many_till
       ( take_while (function
           | 'a' .. 'f' | 'A' .. 'F' | '0' .. '9' -> true
           | _ -> false)
       <* (end_of_line <|> abort "Invalid hex character")
       >>= fun hex ->
         try return (Cstruct.of_hex hex)
         with Invalid_argument msg -> abort msg )
       (string "-----END OpenVPN Static key V1-----" *> a_newline
       <|> abort "Missing END mark")
  <* commit
  <* (skip_many (a_newline <|> a_whitespace) *> end_of_input
     <|> ( pos >>= fun i ->
           abort (Fmt.str "Data after -----END mark at byte offset %d" i) ))
  >>= (fun lst ->
        let sz = Cstruct.lenv lst in
        if 256 = sz then return lst
        else
          abort @@ "Wrong size (" ^ string_of_int sz
          ^ "); need exactly 256 bytes")
  >>| Cstruct.concat
  >>| fun cs ->
  Cstruct.(sub cs 0 64, sub cs 64 64, sub cs 128 64, sub cs (128 + 64) 64)

let a_tls_crypt_v2_client_payload force_cookie =
  ( inline_pem_payload tls_crypt_v2_client_pem_name "tls-crypt-v2" >>= fun cs ->
    if Cstruct.length cs >= 256 + Mirage_crypto.Hash.SHA256.digest_size then
      return cs
    else fail "bad tls-crypt-v2 client key size" )
  >>| fun cs ->
  let key = Cstruct.(sub cs 0 64, sub cs 64 64, sub cs 128 64, sub cs 192 64) in
  let wkc = Cstruct.shift cs 256 in
  B (Tls_crypt_v2_client, (key, wkc, force_cookie))

let a_tls_crypt_v2_server_payload force_cookie =
  ( inline_pem_payload tls_crypt_v2_server_pem_name "tls-crypt-v2" >>= fun cs ->
    if Cstruct.length cs = 128 then return cs
    else fail "bad tls-crypt-v2 server key size" )
  >>| fun cs ->
  let key = Cstruct.(sub cs 0 64, sub cs 64 64) in
  B (Tls_crypt_v2_server, (key, force_cookie))

let a_tls_crypt_v2_payload force_cookie =
  a_tls_crypt_v2_client_payload force_cookie
  <|> a_tls_crypt_v2_server_payload force_cookie

let a_tls_auth_payload direction =
  inline_payload "TLS AUTH" >>| fun (a, b, c, d) ->
  B (Tls_auth, (direction, a, b, c, d))

let split_colon s = String.split_on_char ':' s

let a_tls_cipher =
  string "tls-cipher" *> a_whitespace *> a_line not_control_char
  >>| fun ciphers ->
  `Entry (B (Tls_cipher, List.map cipher_to_cs (split_colon ciphers)))

let a_tls_ciphersuite =
  string "tls-ciphersuite" *> a_whitespace *> a_line not_control_char
  >>| fun ciphers ->
  `Entry (B (Tls_ciphersuite, List.map cipher13_to_cs13 (split_colon ciphers)))

let a_auth_user_pass =
  a_option_with_single_path "auth-user-pass" `Auth_user_pass

let a_secret_payload str =
  match parse_string ~consume:Consume.All (inline_payload "secret") str with
  | Ok (a, b, c, d) -> Ok (B (Secret, (a, b, c, d)))
  | Error e -> Error e

let a_secret =
  a_option_with_single_path "secret" () >>| fun source ->
  match source with
  | `Need_inline () -> `Need_inline `Secret
  | `Path (path, ()) -> `Path (path, `Secret)

let a_ign_whitespace_nl = skip_many (a_newline <|> a_whitespace_unit)

let a_auth_user_pass_payload =
  (* To protect against a client passing a maliciously  formed  user‐
     name  or  password string, the username string must consist only
     of these characters: alphanumeric, underbar ('_'),  dash  ('-'),
     dot  ('.'), or at ('@').  The password string can consist of any
     printable characters except for CR or LF.  Any  illegal  charac‐
     ters in either the username or password string will be converted
     to underbar ('_').*)
  pos
  >>= (fun user_pos ->
        (a_line (function
           | '_' | '-' | '.' | '@' | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' ->
               true
           | _ -> false)
         >>= function
         | "" ->
             ( *> ) commit @@ fail
             @@ Fmt.str
                  "auth-user-pass (byte %d): username is empty, expected on \
                   first line!"
                  user_pos
         | user -> return user)
        >>= fun user ->
        pos >>= fun pass_pos ->
        (a_line not_control_char >>= function
         | "" ->
             ( *> ) commit @@ fail
             @@ Fmt.str
                  "auth-user-pass (byte %d): password is empty, expected on \
                   second line!"
                  pass_pos
         | raw_pass ->
             let bad = ref ~-1 in
             let count = ref 0 in
             String.map
               (function
                 | '\x00' .. '\x1f' | '\x7f' .. '\xff' ->
                     bad := !count;
                     incr count;
                     '_'
                 | ch ->
                     incr count;
                     ch)
               raw_pass
             |> return
             <* return
                @@
                if 0 <= !bad then
                  Log.warn (fun m ->
                      m
                        "config: user-auth-pass at (byte offset %d line offset \
                         %d) contains special character that will be turned \
                         into an underscore '_' , is this intentional?"
                        (pass_pos + !bad) !bad))
        >>= fun pass ->
        a_ign_whitespace_nl *> return (B (Auth_user_pass, (user, pass))))
  <|> fail "reading user/password file failed"

let a_auth_retry =
  string "auth-retry" *> a_whitespace
  *> choice
       [
         string "nointeract" *> return `Nointeract;
         string "interact" *> return `Interact;
         string "none" *> return `None;
       ]
  >>| fun x -> `Entry (B (Auth_retry, x))

let a_socks_proxy =
  string "socks-proxy" *> a_whitespace
  *> take_till (function '\n' | '\t' | ' ' -> false | _ -> true)
  >>= fun server ->
  a_whitespace *> a_number_range 0 65535
  >>= (fun port ->
        a_whitespace *> a_filepath `Socks_proxy
        >>= (function
              | `Path (path, `Socks_proxy) -> return (server, port, `Path path)
              | `Need_inline _ -> fail "socks-proxy not inlineable")
        <|> return (server, port, `Path "stdin"))
  <|> return (server, 1080, `Path "stdin")
  >>| fun x -> `Socks_proxy x

let a_flag =
  let r k v = return (`Entry (B (k, v))) in
  choice
    [
      string "auth-nocache" *> r Auth_nocache ();
      string "bind" *> r Bind (Some (None, None));
      string "nobind" *> r Bind None;
      string "float" *> r Float ();
      string "remote-random" *> r Remote_random ();
      string "tls-client" *> r Tls_mode `Client;
      string "tls-server" *> r Tls_mode `Server;
      string "persist-key" *> r Persist_key ();
      string "persist-tun" *> r Persist_tun ();
      string "comp-lzo no"
      *> return (`Ignored "LZO compression disabled by default");
      string "comp-lzo yes" *> r Comp_lzo ();
      string "comp-lzo" *> r Comp_lzo ();
      (* TODO warn! *)
      string "passtos" *> r Passtos ();
      string "mute-replay-warnings" *> r Mute_replay_warnings ();
      string "ifconfig-nowarn" *> r Ifconfig_nowarn ();
      string "pull" *> r Pull ();
      string "route-nopull" *> r Route_nopull ();
    ]

let a_remote_cert_tls =
  string "remote-cert-tls" *> a_whitespace
  *> choice
       [ string "server" *> return `Server; string "client" *> return `Client ]
  >>| fun purpose -> `Entry (B (Remote_cert_tls, purpose))

let a_hex =
  let is_hex = function
    | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
    | _ -> false
  in
  string "0x" *> take_while1 is_hex >>= fun str ->
  match int_of_string ("0x" ^ str) with
  | i -> return i
  | exception _ -> fail (Fmt.str "Invalid number: %S" str)

let a_tls_version =
  choice
    [
      string "1.3" *> return `TLS_1_3;
      string "1.2" *> return `TLS_1_2;
      string "1.1" *> return `TLS_1_1;
      string "1.0" *> return `TLS_1_0;
    ]

let a_tls_version_min =
  string "tls-version-min" *> a_whitespace *> a_tls_version >>= fun v ->
  choice
    [
      a_whitespace *> string "or-highest" *> return true;
      a_ign_whitespace *> end_of_line *> return false;
    ]
  >>| fun or_h -> `Entry (B (Tls_version_min, (v, or_h)))

let a_tls_version_max =
  string "tls-version-max" *> a_whitespace *> a_tls_version >>| fun v ->
  `Entry (B (Tls_version_max, v))

let a_entry_one_number name =
  let fail off reason =
    fail
    @@ Fmt.str "offset %d: Error parsing %s directive as integer: %s" off name
         reason
  in
  string name *> a_whitespace *> pos >>= fun off ->
  commit *> (a_single_param <|> fail off "parameter needed") >>= fun num ->
  parse_string ~consume:Consume.All a_number num |> function
  | Ok v -> return v
  | Error msg -> fail off msg

let a_tls_timeout =
  a_entry_one_number "tls-timeout" >>| fun seconds ->
  `Entry (B (Tls_timeout, seconds))

let a_reneg_bytes =
  a_entry_one_number "reneg-bytes" >>| fun n ->
  `Entry (B (Renegotiate_bytes, n))

let a_reneg_pkts =
  a_entry_one_number "reneg-pkts" >>| fun n ->
  `Entry (B (Renegotiate_packets, n))

let a_reneg_sec =
  a_entry_one_number "reneg-sec" >>| fun n ->
  `Entry (B (Renegotiate_seconds, n))

let a_lport =
  a_entry_one_number "lport" >>| fun n -> `Entry (B (Bind, Some (Some n, None)))

let a_ipv4_dotted_quad =
  take_while1 (function '0' .. '9' | '.' -> true | _ -> false) >>= fun ip ->
  match Ipaddr.V4.of_string ip with
  | Error (`Msg x) -> fail (Fmt.str "Invalid IPv4: %s: %S" x ip)
  | Ok ip -> return ip

let a_ipv6_coloned_hex =
  take_while1 (function
    | '0' .. '9' | ':' | 'a' .. 'f' | 'A' .. 'F' -> true
    | _ -> false)
  >>= fun ip ->
  match Ipaddr.V6.of_string ip with
  | Error (`Msg x) -> fail (Fmt.str "Invalid IPv6: %s: %S" x ip)
  | Ok ip -> return ip

let a_ip =
  a_ipv4_dotted_quad
  >>| (fun v4 -> Ipaddr.V4 v4)
  <|> (a_ipv6_coloned_hex >>| fun v6 -> Ipaddr.V6 v6)

let a_domain_name =
  take_till (function
    | '\x00' .. '\x1f' | ' ' | '"' | '\'' -> true
    | _ -> false)
  >>= fun str ->
  match Domain_name.of_string str with
  | Error (`Msg x) -> fail (Fmt.str "Invalid domain name: %s: %S" x str)
  | Ok x -> (
      match Domain_name.host x with
      | Error (`Msg x) -> fail (Fmt.str "Invalid host name: %s: %S" x str)
      | Ok x -> return x)

let a_domain_or_ip =
  a_single_param >>= fun param ->
  Angstrom.parse_string ~consume:Consume.All
    (choice ~failure_msg:"not a hostname nor an IP"
       [
         (a_ip >>| fun ip -> `Ip ip); (a_domain_name >>| fun dns -> `Domain dns);
       ])
    param
  |> function
  | Ok x -> return x
  | Error s -> fail s

let a_verify_x509_name =
  string "verify-x509-name" *> a_whitespace *> a_domain_name >>= fun v ->
  option "subject" (a_whitespace *> a_single_param) >>| fun t ->
  match t with
  | "name" -> `Entry (B (Verify_x509_name, v))
  | _ -> failwith ("verify-x509-name: only type = name supported, not: " ^ t)

let a_local =
  string "local" *> a_whitespace *> a_domain_or_ip >>| fun dom ->
  `Entry (B (Bind, Some (None, Some dom)))

let a_rport = a_entry_one_number "rport" >>| fun n -> `Rport n

let a_ping =
  (a_entry_one_number "ping" >>| function
   | 0 -> `Not_configured
   | n -> `Seconds n)
  >>| fun setting -> `Entry (B (Ping_interval, setting))

let a_ping_restart =
  a_entry_one_number "ping-restart" >>| fun n ->
  `Entry (B (Ping_timeout, `Restart n))

let a_ping_exit =
  a_entry_one_number "ping-exit" >>| fun n -> `Entry (B (Ping_timeout, `Exit n))

let a_link_mtu =
  a_entry_one_number "link-mtu" >>| fun x -> `Entry (B (Link_mtu, x))

let a_tun_mtu =
  a_entry_one_number "tun-mtu" >>| fun x -> `Entry (B (Tun_mtu, x))

let a_hand_window =
  string "hand-window" *> a_whitespace *> a_number_range 0 86400
  >>| fun seconds -> `Entry (B (Handshake_window, seconds))

let a_tran_window =
  string "tran-window" *> a_whitespace *> a_number_range 0 86400
  >>| fun seconds -> `Entry (B (Transition_window, seconds))

let a_mssfix = a_entry_one_number "mssfix" >>| fun x -> `Entry (B (Mssfix, x))
(* TODO make a_mssfix use a_number_range *)

let a_entry_two_numbers name =
  a_entry_one_number name >>= fun x ->
  a_whitespace *> a_number >>| fun y -> (x, y)

let a_connect_retry =
  a_entry_two_numbers "connect-retry" >>| fun pair ->
  `Entry (B (Connect_retry, pair))

let a_connect_retry_max =
  string "connect-retry-max" *> a_whitespace
  *> choice
       [
         (a_number_range 0 max_int >>| fun i -> `Times i);
         string "unlimited" *> return `Unlimited;
       ]
  >>| fun times -> `Entry (B (Connect_retry_max, times))

let a_connect_timeout =
  choice
    [
      a_entry_one_number "connect-timeout";
      a_entry_one_number "server-poll-timeout";
    ]
  >>| fun seconds -> `Entry (B (Connect_timeout, seconds))

let a_keepalive =
  a_entry_two_numbers "keepalive" >>= function
  | 0, _ -> fail "keepalive 0 [..] must be >= 0"
  | interval, timeout -> return (`Keepalive (interval, timeout))

let a_verb = a_entry_one_number "verb" >>| fun x -> `Entries [ B (Verb, x) ]

let a_topology =
  string "topology" *> a_whitespace
  *> choice
       [
         string "net30" *> return `Net30;
         string "p2p" *> return `P2p;
         string "subnet" *> return `Subnet;
       ]
  >>| fun v -> `Entry (B (Topology, v))

let a_port =
  string "port" *> a_whitespace *> a_number_range 0 65535 >>| fun port ->
  `Entry (B (Port, port))

let a_auth_user_pass_verify =
  let path = take_while1 (function ' ' -> false | _ -> true) in
  let aupv a b = `Entry (B (Auth_user_pass_verify, (a, b))) in
  lift2 aupv
    (string "auth-user-pass-verify" *> a_whitespace *> path)
    (a_whitespace
    *> choice
         [
           string "via-env" *> return `Via_env;
           string "via-file" *> return `Via_file;
         ])

let a_script_security =
  string "script-security" *> a_whitespace *> a_number >>| fun ss ->
  `Entry (B (Script_security, ss))

let a_verify_client_cert =
  string "verify-client-cert"
  *> a_whitespace
  *> choice
       [
         string "none" *> return `None;
         string "optional" *> return `Optional;
         string "require" *> return `Required;
       ]
  >>| fun v -> `Entry (B (Verify_client_cert, v))

let a_server =
  string "server" *> a_whitespace *> a_ipv4_dotted_quad >>= fun address ->
  a_whitespace *> a_ipv4_dotted_quad >>= fun netmask ->
  match Ipaddr.V4.Prefix.of_netmask ~netmask ~address with
  | Ok cidr -> return (`Entry (B (Server, cidr)))
  | Error (`Msg m) -> fail m

let a_cipher =
  string "cipher" *> a_whitespace *> a_single_param >>| fun v ->
  `Entry (B (Cipher, v))

let a_replay_window =
  let replay_window a b = `Entry (B (Replay_window, (a, b))) in
  lift2 replay_window
    (string "replay-window" *> a_whitespace *> a_number)
    (option 15 (a_whitespace *> a_number))

let a_ifconfig =
  string "ifconfig" *> a_whitespace *> a_ip >>= fun local ->
  a_whitespace *> a_ip >>| fun remote -> `Entry (B (Ifconfig, (local, remote)))

(* TODO
   what are the semantics if proto and remote proto is provided? *)
let a_remote :
    [> `Remote of
       [ `Domain of [ `host ] Domain_name.t * [ `Ipv6 | `Ipv4 | `Any ]
       | `Ip of Ipaddr.t ]
       * [ `Port of int | `Default_rport ]
       * [ `Udp | `Tcp ] option ]
    A.t =
  string "remote" *> a_whitespace *> a_domain_or_ip >>= fun host_or_ip ->
  ( option `Default_rport (a_whitespace *> a_number >>| fun p -> `Port p)
  >>= fun port ->
    (option None (a_whitespace *> a_single_param >>| fun p -> Some p)
     >>= function
     | Some "udp" -> return (Some `Udp, `Any)
     | Some "udp4" -> return (Some `Udp, `Ipv4)
     | Some "udp6" -> return (Some `Udp, `Ipv6)
     | Some "tcp" -> return (Some `Tcp, `Any)
     | Some "tcp4" -> return (Some `Tcp, `Ipv4)
     | Some "tcp6" -> return (Some `Tcp, `Ipv6)
     | Some x -> fail (Fmt.str "remote: unknown protocol designation %S" x)
     | None -> return (None, `Any))
    >>| fun protos -> (port, protos) )
  >>= fun (port, protos) ->
  match (host_or_ip, protos) with
  | `Domain host, (dp, ipv) -> return @@ `Remote (`Domain (host, ipv), port, dp)
  | `Ip (Ipaddr.V4 _ as i), (dp, (`Any | `Ipv4)) ->
      return @@ `Remote (`Ip i, port, dp)
  | `Ip (Ipaddr.V6 _ as i), (dp, (`Any | `Ipv6)) ->
      return @@ `Remote (`Ip i, port, dp)
  | `Ip ip, (_, ((`Ipv4 | `Ipv6) as v)) ->
      fail
        (Fmt.str "remote: ip addr %a is required to be %s." Ipaddr.pp ip
           (match v with `Ipv4 -> "IPv4" | `Ipv6 -> "IPv6"))

let a_remote_entry = a_remote

let a_network_or_gateway =
  choice
    [
      (a_ip >>| fun ip -> `Ip ip);
      string "vpn_gateway" *> return `Vpn_gateway;
      string "net_gateway" *> return `Net_gateway;
      string "remote_host" *> return `Remote_host;
    ]

let a_route =
  (* --route network/IP [netmask] [gateway] [metric] *)
  string "route" *> a_whitespace *> a_network_or_gateway >>= fun network ->
  let some x = Some x in

  option
    (some @@ Ipaddr.Prefix.of_string_exn "255.255.255.255/32", None, `Default)
    ( a_whitespace
    *> (a_ip
       >>= (fun ip ->
             char '/' *> a_number_range 0 32 >>= fun mask ->
             match
               Ipaddr.Prefix.of_string (Fmt.str "%a/%d" Ipaddr.pp ip mask)
             with
             | Error (`Msg err) -> fail err
             | Ok n -> return n)
       <|> (choice
              [
                string "default"
                *> return (Ipaddr.of_string_exn "255.255.255.255");
                a_ip;
              ]
           >>| Ipaddr.Prefix.of_addr)
       >>| some)
    >>= fun netmask ->
      option (None, `Default)
        ( a_whitespace
        *> (string "default" *> return None <|> (a_network_or_gateway >>| some))
        >>= fun gateway ->
          (* read metric: *)
          option `Default
            (a_whitespace
            *> (string "default" *> return `Default
               <|> (a_number_range 0 255 >>| fun i -> `Metric i)))
          >>| fun metric -> (gateway, metric) )
      >>| fun (gateway, metric) -> (netmask, gateway, metric)
      (* <* end_of_input*) )
  >>| fun (netmask, gateway, metric) ->
  `Entry (B (Route, [ (network, netmask, gateway, metric) ]))

let a_route_gateway =
  string "route-gateway" *> a_whitespace
  *> choice
       [
         (a_single_param >>= function
          | "dhcp" -> return `Dhcp
          | "default" -> return `Default
          | _ -> fail "not dhcp|default|ip");
         (a_ip >>| fun x -> `Ip x);
       ]
  >>| fun x -> `Entry (B (Route_gateway, x))

let a_inline =
  char '<'
  *> take_while1 (function 'a' .. 'z' | '0' .. '9' | '-' -> true | _ -> false)
  <* char '>' <* a_newline
  >>= fun tag ->
  skip_many (a_whitespace_or_comment *> end_of_line)
  *> take_till (function '<' -> true | _ -> false)
  >>= fun x ->
  return (`Inline (tag, x))
  <* skip_many end_of_line <* char '<' <* char '/' <* string tag <* char '>'

let a_dhcp_option =
  (string "dhcp-option" *> a_whitespace *> a_single_param
   >>| String.lowercase_ascii
   >>= function
   | "disable-nbt" -> return @@ B (Dhcp_disable_nbt, ())
   | "dns" -> a_whitespace *> a_ip >>| fun ip -> B (Dhcp_dns, [ ip ])
   | "domain" -> a_whitespace *> a_domain_name >>| fun d -> B (Dhcp_domain, d)
   | "ntp" -> a_whitespace *> a_ip >>| fun ip -> B (Dhcp_ntp, [ ip ])
   | _ -> fail "Unrecognized dhcp-option type")
  >>| fun b -> `Entry b

let a_not_implemented =
  choice
    [
      string "sndbuf";
      string "rcvbuf";
      string "inactive";
      string "ip-win32";
      string "socket-flags";
      string "remote-cert-ku";
      string "engine";
      string "ifconfig-pool-persist";
      string "status";
      string "log-append";
      string "log";
      (* TODO: *)
      string "redirect-gateway";
      string "up";
      string "dh";
      string "explicit-exit-notify";
    ]
  <* a_whitespace
  >>= fun key ->
  a_line not_control_char >>| fun rest ->
  Log.warn (fun m -> m "IGNORING %S %S" key rest);
  `Ignored (key ^ " " ^ rest)

let a_config_entry : line A.t =
  a_ign_whitespace_no_comment
  *> Angstrom.choice
       [
         a_client;
         a_dev;
         a_dev_type;
         a_local;
         a_dhcp_option;
         a_proto;
         a_proto_force;
         a_resolv_retry;
         a_tls_auth;
         a_tls_timeout;
         a_tls_crypt_v2;
         a_remote_cert_tls;
         a_verb;
         a_hand_window;
         a_tran_window;
         a_connect_retry;
         a_connect_retry_max;
         a_connect_timeout;
         a_auth_retry;
         a_mssfix;
         a_inline;
         a_tls_version_min;
         a_keepalive;
         a_socks_proxy;
         a_auth_user_pass_verify;
         a_auth_user_pass;
         a_link_mtu;
         a_tun_mtu;
         a_cipher;
         a_port;
         a_server;
         a_verify_client_cert;
         a_script_security;
         a_replay_window;
         a_remote;
         a_reneg_bytes;
         a_reneg_pkts;
         a_reneg_sec;
         a_lport;
         a_rport;
         a_pkcs12;
         a_flag;
         a_ca;
         a_cert;
         a_key;
         a_ping;
         a_ping_restart;
         a_ping_exit;
         a_ifconfig;
         a_topology;
         a_route;
         a_route_gateway;
         a_topology;
         a_tls_ciphersuite;
         a_tls_cipher;
         a_secret;
         a_verify_x509_name;
         a_not_implemented;
         a_whitespace *> return (`Ignored "");
       ]

let parse_internal config_str : (line list, 'x) result =
  let a_ign_ws =
    skip_many (skip @@ function '\r' | '\n' | ' ' | '\t' -> true | _ -> false)
  in
  config_str
  |> parse_string ~consume:Consume.All
     @@ fix (fun recurse ->
            a_ign_ws *> a_config_entry <* a_ign_ws
            >>= (fun entry ->
                  commit
                  *> (a_ign_ws *> end_of_input *> return [ entry ]
                     <|> (List.cons entry <$> recurse)))
            <|> ( available >>| min 100 >>= peek_string >>= fun context ->
                  pos >>= fun pos ->
                  fail
                    (Printf.sprintf "Error at byte offset %d: %S" pos context)
                ))

type parser_partial_state = line list * Conf_map.t

type parser_state =
  [ `Done of Conf_map.t
  | `Partial of parser_partial_state
  | `Need_file of string * parser_partial_state ]

type parser_effect = [ `File of string * string ] option

let parse_inline str = function
  | `Auth_user_pass ->
      (* TODO openvpn doesn't seem to allow inlining passwords, we do.. *)
      parse_string ~consume:Consume.All a_auth_user_pass_payload str
  | `Tls_auth direction ->
      parse_string ~consume:Consume.All (a_tls_auth_payload direction) str
  | `Connection ->
      let open Result.Infix in
      (* TODO entries can sometimes be nested, like in <connection> blocks:
         The following OpenVPN options may be used inside of  a  <connection> block:
         bind,  connect-retry,  connect-retry-max,  connect-timeout,
         explicit-exit-notify, float, fragment, http-proxy,  http-proxy-option,
         link-mtu, local, lport, mssfix, mtu-disc, nobind, port,
         proto, remote, rport, socks-proxy, tun-mtu and tun-mtu-extra. *)
      (* TODO basically a Connection block is a subset of Conf_map.t,
         we should use the same parser.*)
      parse_string ~consume:Consume.All a_remote str
      >>= fun (`Remote (host, port, proto)) ->
      (* TODO consult `Proto and `Proto_force *)
      let proto = match proto with None -> `Udp | Some x -> x in
      let port = match port with `Default_rport -> 1194 | `Port i -> i in
      Ok (B (Remote, [ (host, port, proto) ]))
  | `Ca -> a_ca_payload str
  | `Tls_cert -> a_cert_payload str
  | `Tls_key -> a_key_payload str
  | `Tls_crypt_v2 force_cookie ->
      parse_string ~consume:Consume.All
        (a_tls_crypt_v2_payload force_cookie)
        str
  | `Secret -> a_secret_payload str
  | kind ->
      Error
        ("config-parser: not sure how to parse inline "
       ^ string_of_inlineable kind)

let eq : eq =
  {
    f =
      (fun (type x) (k : x k) (v : x) (v2 : x) ->
        match (k, v, v2) with
        | Secret, (a, b, c, d), (a', b', c', d') ->
            Cstruct.equal a a' && Cstruct.equal b b' && Cstruct.equal c c'
            && Cstruct.equal d d'
        | Tls_auth, (dir, a, b, c, d), (dir', a', b', c', d') ->
            dir = dir' && Cstruct.equal a a' && Cstruct.equal b b'
            && Cstruct.equal c c' && Cstruct.equal d d'
        | Remote, remotes_lst, remotes_lst2 ->
            List.for_all2
              (fun (a, port1, proto1) (b, port2, proto2) ->
                port1 = port2 && proto1 = proto2
                &&
                match (a, b) with
                | `Domain (host_a, ipv_a), `Domain (host_b, ipv_b) ->
                    ipv_a = ipv_b && Domain_name.equal host_a host_b
                | `Ip a, `Ip b -> 0 = Ipaddr.compare a b
                | (`Domain _ | `Ip _), (`Domain _ | `Ip _) -> false)
              remotes_lst remotes_lst2
        | ( Tls_crypt_v2_client,
            ((a, b, c, d), wkc, force_cookie),
            ((a', b', c', d'), wkc', force_cookie') ) ->
            Cstruct.equal a a' && Cstruct.equal b b' && Cstruct.equal c c'
            && Cstruct.equal d d' && Cstruct.equal wkc wkc'
            && force_cookie = force_cookie'
        | _ ->
            (*TODO non-polymorphic comparison*)
            let eq = v = v2 in
            Log.debug (fun m ->
                m "eq self-test: @[<v>%a@, %s @,%a@]" pp (singleton k v)
                  (if eq then "=" else "<>")
                  pp (singleton k v2));
            eq);
  }

let resolve_conflict (type a) t (k : a key) (v : a) :
    ((a key * a) option, _) result =
  (* when called by merge_push_reply, [v] is the server-provided value,
     and [t] is the local configuration *)
  let warn () =
    Log.debug (fun m ->
        m "Configuration flag appears twice: %a" pp (singleton k v));
    Ok None
  in
  match find k t with
  | None -> Ok (Some (k, v))
  | Some v2 -> (
      match k with
      (* idempotent, as most of the flags - not a failure, emit warn: *)
      | Auth_nocache -> warn ()
      | Comp_lzo -> warn ()
      | Float -> warn ()
      | Ifconfig_nowarn -> warn ()
      | Mute_replay_warnings -> warn ()
      | Passtos -> warn ()
      | Persist_key -> warn ()
      | Persist_tun -> warn ()
      | Pull -> warn ()
      | Remote_random -> warn ()
      (* last one wins *)
      | Verb ->
          Log.debug (fun m ->
              m
                "Configuration flag 'verb' appears twice: %u vs %u, the former \
                 is used"
                v2 v);
          Ok (Some (k, v2))
      (* can be pushed, but can't change: *)
      | Auth_retry ->
          Log.warn (fun m ->
              m
                "resolve_conflict: ignoring Auth_retry (should only be done \
                 when called from merge_push_reply. TODO.");
          Ok (Some (k, v2))
      (* can coalesce: *)
      | Bind -> (
          match (v, v2) with
          | None, None -> Ok (Some (Bind, None))
          | Some _, None | None, Some _ ->
              Error "Conflicting [bind] directives."
          | Some v, Some v2 ->
              let open Result.Infix in
              (match (fst v, fst v2) with
              (* coalesce port binding *)
              | (Some _ as x), None -> Ok x
              | None, (Some _ as x) -> Ok x
              | v1, v2 when v1 = v2 -> Ok v1
              | _ -> Error "conflicting [port] options in [bind] directives")
              >>= fun (port : int option) ->
              (match (snd v, snd v2) with
              (* coalesce host/ip binding *)
              | (Some _ as x), None -> Ok x
              | None, (Some _ as x) -> Ok x
              | v1, v2 when v1 = v2 -> Ok v1
              | _ -> Error "conflicting [host] options in [bind] directives")
              >>= fun (host : _ option) -> Ok (Some (Bind, Some (port, host))))
      | Dev when fst v = fst v2 -> (
          (* verify that dev-type is the same, and let Dev stanza
             override an empty name.*)
          match (snd v, snd v2) with
          | None, (Some _ as name) | ((None | Some _) as name), None ->
              Ok (Some (Dev, (fst v2, name)))
          | Some n, Some n2 ->
              Error (Fmt.str "[dev %S] conflicts with [dev %S]" n n2))
      | Dhcp_dns -> Ok (Some (Dhcp_dns, get Dhcp_dns t @ v))
      | Dhcp_ntp -> Ok (Some (Dhcp_ntp, get Dhcp_ntp t @ v))
      | Remote -> (
          match (find Remote t, v) with
          | Some [], [] | None, [] -> Ok None (* prune empty *)
          | Some peers1, peers2 -> Ok (Some (Remote, peers1 @ peers2))
          | None, peers2 -> Ok (Some (Remote, peers2)))
      | Ping_interval ->
          (match find Ping_interval t with
          | Some old when old <> v ->
              Log.warn (fun m ->
                  m "Overriding previous interval %d with %d"
                    (int_of_ping_interval old) (int_of_ping_interval v))
          | _ -> ());
          Ok (Some (k, v))
      | Ping_timeout -> (
          let override ~old ~next =
            if old <> next then
              Log.warn (fun m ->
                  m "Overriding previous ping timeout %d with %d" old next);
            Ok (Some (k, v))
          in
          match (v, find Ping_timeout t) with
          | _, None -> Ok (Some (k, v))
          | `Exit next, Some (`Exit old) -> override ~old ~next
          | `Restart next, Some (`Restart old) -> override ~old ~next
          | `Exit _, Some (`Restart _) ->
              Error
                "Remote config tried to change ping timeout action from \
                 'restart' to 'exit'"
          | `Restart _, Some (`Exit _) ->
              Error
                "Remote config tried to change ping timeout action from 'exit' \
                 to 'restart'")
      (* adding wouldn't change anything: *)
      | _ when v = v2 ->
          (* TODO polymorphic comparison *)
          Log.debug (fun m ->
              m "Config key %a was supplied multiple times with same value" pp
                (singleton k v));
          Ok None
      (* else: *)
      | _ ->
          Error
            (Fmt.str "conflicting keys: %a not in %a" pp (singleton k v) pp t))

let resolve_add_conflict t (B (k, v)) =
  let open Result.Infix in
  resolve_conflict t k v >>| function Some (k, v) -> add k v t | None -> t

let valid_server_options ~client:_ _server_t =
  Log.err (fun m -> m "TODO valid_server_options is not implemented");
  Ok ()

let parse_next (effect : parser_effect) initial_state :
    (parser_state, 'err) result =
  let open Result.Infix in
  let rec loop (acc : Conf_map.t) : line list -> (parser_state, 'b) result =
    function
    | (hd : line) :: tl -> (
        (* TODO should make sure not to override without conflict resolution,
           ie use addb_unless_bound and so on... *)
        let multib ?(tl = tl) kv =
          List.fold_left
            (fun acc b ->
              acc >>= fun acc ->
              match resolve_add_conflict acc b with
              | Ok _ as next -> next
              | Error err ->
                  Log.debug (fun m -> m "%S : %a" err pp acc);
                  Error err)
            (Ok acc) kv
          >>= fun acc -> loop acc tl
        in
        let retb ?tl b = multib ?tl [ b ] in
        match hd with
        | `Path (wanted_name, kind) -> (
            match effect with
            | Some (`File (effect_name, content))
              when String.equal effect_name wanted_name ->
                (* TODO ensure returned B matches kind? *)
                Result.map_error
                  (fun x -> "failed parsing provided file: " ^ x)
                  (parse_inline content kind)
                >>= retb
            | _ -> Ok (`Need_file (wanted_name, (hd :: tl, acc))))
        | `Need_inline kind -> (
            let looking_for = string_of_inlineable kind in
            match
              List.partition
                (function
                  | `Inline (kind2, _) -> String.equal looking_for kind2
                  | _ -> false)
                tl
            with
            | `Inline (_, x) :: inline_tl, other_tl ->
                Log.debug (fun m -> m "consuming [inline] %s" looking_for);
                parse_inline x kind >>= resolve_add_conflict acc >>= fun acc ->
                loop acc (other_tl @ inline_tl)
            | [], _ ->
                (* TODO if we already have it in the map, we don't need to fail: *)
                Error ("not found: needed [inline]: " ^ looking_for)
            | _ -> Error "TODO List.partition was wrong")
        | `Inline ("connection", x) ->
            parse_inline x `Connection >>= resolve_add_conflict acc
            >>= fun acc -> loop acc tl
        | `Inline ("secret", payload) ->
            parse_inline payload `Secret >>= resolve_add_conflict acc
            >>= fun acc -> loop acc tl
        | `Inline (fname, _) ->
            (* Except for "connection" all blocks must be warranted by an
               [inline] value in a matching directive. If we have one, we move
               this block to the end of the list (since we -know- it's needed).
               If not, we ignore it after emitting an error: *)
            loop acc @@ tl
            @
            if
              List.exists
                (function
                  | `Need_inline k
                    when String.equal fname (string_of_inlineable k) ->
                      true
                  | _ -> false)
                tl
            then [ hd ]
            else (
              Log.warn (fun m ->
                  m "Inline block %S seems to be redundant" fname);
              [])
        | `Ignored _ -> loop acc tl
        | `Comment _ -> loop acc tl
        | `Rport _ as this_directive ->
            (* The parser for `Remote will look for `Rport when needed.
               To avoid an endless loop here we ignore the present `Rport
               directive when no more `Remote exist in [tl].
               If there ARE more `Remote (that use `Default_port),
               we sort [tl] in this order:
               [`Remote ; `Rport ; ... the rest]:
            *)
            if
              not
              @@ List.exists
                   (function
                     | `Remote (_, `Default_rport, _) -> true | _ -> false)
                   tl
            then multib [] (* ignore this directive*)
            else
              let sorted_tl =
                List.sort
                  (fun a b ->
                    match (a, b) with
                    | `Remote _, `Rport _ -> -1 (* remote goes first *)
                    | `Rport _, `Remote _ -> 1 (* remote goes first *)
                    | _ -> compare a b)
                  (this_directive :: tl)
              in
              loop acc sorted_tl
        | `Entry b -> retb b
        | `Entries lst -> multib lst
        | `Keepalive (interval, timeout) ->
            (match find Ping_interval acc with
            | Some old ->
                Log.warn (fun m ->
                    m "keepalive %d %d overrides former ping interval %d"
                      interval timeout (int_of_ping_interval old))
            | None -> ());
            let acc = add Ping_interval (`Seconds interval) acc in
            let keepalive_action was_old next =
              let maybe_warn old =
                if was_old && old <> next then
                  Log.warn (fun m ->
                      m "keepalive %d %d overrides former ping timeout %d"
                        interval timeout old)
              in
              function
              | `Exit old ->
                  maybe_warn old;
                  `Exit next
              | `Restart old ->
                  maybe_warn old;
                  `Restart next
            in
            let timeout =
              let was_old, action =
                match find Ping_timeout acc with
                | Some old -> (true, old)
                | None -> (
                    match
                      List.find_opt
                        (function
                          | `Entry (B (Ping_timeout, _)) -> true | _ -> false)
                        tl
                    with
                    | Some (`Entry (B (Ping_timeout, x))) -> (false, x)
                    | _ -> (false, get Ping_timeout Defaults.common))
              in
              keepalive_action was_old timeout action
            in
            loop (add Ping_timeout timeout acc) tl
        | (`Proto_force _ | `Socks_proxy _) as line ->
            Log.warn (fun m ->
                m "ignoring unimplemented option: %a" pp_line line);
            multib []
        | `Remote (host, port, proto) -> (
            let proto =
              match proto with
              | Some x -> x
              | None -> (
                  match Conf_map.find Proto acc with
                  | Some (_, `Tcp _) -> `Tcp
                  | _ -> `Udp)
            in
            (* TODO consult `Proto_force *)
            let rec consult_tl ?rport = function
              | [] -> Ok rport
              | `Rport conf :: _ when rport <> None && Some conf <> rport ->
                  Error
                    (Fmt.str "conflicting rport directives: %d <> %a" conf
                       Fmt.(option int)
                       rport)
              | `Rport rport :: tl -> consult_tl ~rport tl
              | _hd :: tl -> consult_tl ?rport tl
            in
            match port with
            | `Default_rport ->
                (consult_tl tl >>| function
                 | None -> 1194 (* hardcoded default *)
                 | Some port -> port)
                >>= fun port -> retb (B (Remote, [ (host, port, proto) ]))
            | `Port port -> retb (B (Remote, [ (host, port, proto) ])))
        | (`Dev _ | `Dev_type _) as current -> (
            (* there must be a corresponding `Dev or `Dev_type in [tl]*)
            let typs, names, tl =
              List.fold_left
                (fun (typs, nams, other) -> function
                  | `Dev_type typ -> (typ :: typs, nams, other)
                  | `Dev name -> (typs, name :: nams, other)
                  | o -> (typs, nams, o :: other)
                  (* o::other reverses the list, in order to keep
                     Remote and other order-sensitive stanzas intact
                     we need to List.rev the [tl] list. *))
                ([], [], []) (current :: tl)
            in
            let tl = List.rev tl in
            (* Fix [tl] ordering *)
            match (typs, names) with
            | [ typ ], [ name ] ->
                (* custom named tun/tap device: *)
                retb ~tl (B (Dev, (typ, Some name)))
            | [ typ ], [] -> (
                (* extraneous dev-type stanzas when dev-type has already been
                   inferred from the device name, e.g. "tun0" *)
                match find Dev acc with
                | Some (typ2, _name) when typ = typ2 -> loop acc tl
                | Some (_, _name) ->
                    Error
                      (Fmt.str
                         "dev-type %S conflicts with inferred type for [dev] \
                          stanza"
                         (match typ with `Tap -> "tap" | `Tun -> "tun"))
                | None -> retb ~tl (B (Dev, (typ, None))))
            | [], [] -> Error "BUG in config parser: `Dev|`Dev_type empty list"
            | [], name :: _extra_devs ->
                Error
                  (Fmt.str "[dev %S] stanza without required [dev-type]" name)
            | _ -> Error "multiple conflicting [dev-type] stanzas present"))
    | [] -> Ok (`Done acc : parser_state)
  in
  match initial_state with
  | `Done _ as ret -> Ok ret (* already done*)
  | `Partial (lines, acc) -> loop acc lines
  | `Need_file (_fn, (lines, acc)) -> loop acc lines

let parse_begin config_str : (parser_state, 'err) result =
  let open Result.Infix in
  parse_internal config_str >>= fun lines ->
  parse_next None (`Partial (lines, empty))

let parse ~string_of_file config_str : (Conf_map.t, [> `Msg of string ]) result
    =
  let open Result.Infix in
  let to_msg t = Result.map_error (fun s -> `Msg s) t in
  let rec loop = function
    | `Done conf -> Ok conf
    | `Partial _ as t -> parse_next None t |> to_msg >>= loop
    | `Need_file (fn, t) ->
        string_of_file fn >>= fun contents ->
        parse_next (Some (`File (fn, contents))) (`Partial t) |> to_msg >>= loop
  in
  parse_begin config_str |> to_msg >>= fun initial ->
  (loop initial
    : (_, [< `Msg of string ]) result
    :> (_, [> `Msg of string ]) result)

let parse_client ~string_of_file config_str =
  let open Result.Infix in
  parse ~string_of_file config_str >>= fun parsed_conf ->
  (* apply default configuration entries, overriding with the parsed config: *)
  let merged =
    Conf_map.union
      { f = (fun _key _default parsed -> Some parsed) }
      Defaults.client parsed_conf
  in
  is_valid_client_config merged >>| fun () -> merged

let parse_server ~string_of_file config_str =
  let open Result.Infix in
  parse ~string_of_file config_str >>= fun parsed_conf ->
  (* apply default configuration entries, overriding with the parsed config: *)
  let merged =
    Conf_map.union
      { f = (fun _key _default parsed -> Some parsed) }
      Defaults.server parsed_conf
  in
  is_valid_server_config merged >>| fun () -> merged

let merge_push_reply client (push_config : string) =
  let open Result.Infix in
  String.split_on_char ',' push_config
  |> String.concat "\n"
  |> parse ~string_of_file:(fun _ ->
         Result.error_msgf "string of file is not available")
  >>= fun push_config ->
  let will_accept (type a) (k : a key) (v : a) =
    match (k, v) with
    (* whitelist keys we are willing to accept from server: *)
    | Dhcp_disable_nbt, _ -> not (Conf_map.mem Route_nopull client)
    | Dhcp_domain, _ -> not (Conf_map.mem Route_nopull client)
    | Mssfix, _ -> true
    | Tls_mode, `Client -> true
    | Tun_mtu, _ -> true
    | Topology, _ -> true
    | Renegotiate_seconds, n when n > 0 -> true
    | Ping_interval, `Seconds n when n >= 0 -> true
    | Ping_timeout, `Restart n when n >= 0 ->
        true (* TODO | Redirect_gateway, _ -> true *)
    (* TODO should verify IPs: *)
    | Dhcp_dns, _ -> not (Conf_map.mem Route_nopull client)
    | Dhcp_ntp, _ -> not (Conf_map.mem Route_nopull client)
    | Ifconfig, _ -> true
    | Route, _ -> not (Conf_map.mem Route_nopull client)
    | Route_gateway, _ -> not (Conf_map.mem Route_nopull client)
    | _ -> false
  in
  (* let naughty_server = in *)
  let f (type a) (k : a key) (a : a option) (b : a option) =
    match (k, (a : a option), (b : a option)) with
    (* server didn't touch this key: *)
    | _, (Some _ as a), None -> a
    | _, None, None -> None
    (* Client overrides list completely if set: *)
    (* TODO all keys with type 'a list k should probably be listed here,
       can we ensure that statically? *)
    | Dhcp_dns, (Some _ as a), Some _ -> a
    | Dhcp_ntp, (Some _ as a), Some _ -> a
    (* TODO | Route, Some a, _ -> a*)
    (* try to merge: *)
    | _, (Some a as some_a), Some b -> (
        match (a, b) with
        (* they're equal, use client version: *)
        | _ when eq.f k a b -> some_a
        | _ when not (will_accept k b) ->
            invalid_arg
            @@ Fmt.str "push-reply: won't accept %a" pp (singleton k b)
        (* at this point we need to merge them*)
        | a, b -> (
            match resolve_conflict (singleton k a) k b with
            | Ok (Some (_, merged)) -> Some merged
            (* client takes precedence if merging fails: *)
            | _ -> some_a))
    (* try to use server value: *)
    | _, None, Some v ->
        if will_accept k v then b (* <-- use server version *)
        else
          invalid_arg
          @@ Fmt.str "server pushed disallowed: %a" pp (singleton k v)
  in
  try Ok (merge { f } client push_config)
  with Invalid_argument msg -> Error (`Msg msg)

let client_generate_connect_options t =
  (* This uses a different format, notably config directives are separated by
     commas instead of newlines.
     These are used by the server when it is run with --opt-verify
  *)
  (* Ok "V4,dev-type tun,link-mtu 1560,tun-mtu 1500,proto TCPv4_CLIENT,\
     keydir 1,cipher AES-256-CBC,auth SHA1,keysize 256,tls-auth,\
     key-method 2" *)
  let open Result.Infix in
  Conf_map.is_valid_client_config t >>= fun () ->
  let excerpt =
    Conf_map.filter
      (function
        | B (Cipher, _) -> true
        | B (Comp_lzo, _) -> true
        | B (Tun_mtu, _) -> true
        | B (Link_mtu, _) -> true
        | B (Pull, _) -> true
        | B (Tls_mode, `Client) -> true
        | _ -> false)
      t
  in
  let serialized =
    Fmt.str "V4,tls-client,%s%a"
      (match Conf_map.find Dev t with
      | Some (`Tun, _) -> "dev-type tun,"
      | Some (`Tap, _) -> "dev-type tap,"
      | _ -> "")
      (Conf_map.pp_with_sep ~sep:(Fmt.any ","))
      excerpt
  in
  Log.warn (fun m ->
      m "serialized connect options, probably incorrect: %S" serialized);
  Ok serialized

let server_generate_connect_options _config =
  "V4,dev-type tun,link-mtu 1559,tun-mtu 1500,proto TCPv4_SERVER,keydir \
   0,cipher AES-256-CBC,auth SHA1,keysize 256,tls-auth,key-method 2,tls-server"

let client_merge_server_config client server_str =
  (* TODO: Mutate client config,
     for instance choosing [tun-mtu = min (server,client)].
  *)
  Log.warn (fun m ->
      m "Config.client_merge_server_config @[<v>is not implemented@ %S@]"
        server_str);
  Ok client
(* String.split_on_char ',' server_str
   |> String.concat "\n"
   |> parse ~string_of_file:(fun fn ->
        Result.error_msgf "Server requested client to read %S" fn)
    >>= valid_server_options ~client >>| fun () -> client*)

include Conf_map

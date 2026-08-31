# mlx5 ethtool -L Trace Map (clickable)

This map follows:

ethtool -L ens7f0np0 combined 2

from userspace syscall entry to mlx5 driver queue recreation and firmware command execution.

Legend:

- What it does: why this function is on the path.
- Key data: main arguments/fields involved.
- Transition: which function is called next in the flow.

## 1) Syscall and netlink ingress

1. [sendmsg syscall entry](kernel/net6p8/net/socket.c#L2674)
What it does: userspace ethtool netlink message enters kernel through syscall ABI.
Key data: fd (netlink socket), user_msghdr, flags.
Transition: goes to __sys_sendmsg.

2. [__sys_sendmsg](kernel/net6p8/net/socket.c#L2653)
What it does: resolves file descriptor to struct socket and dispatches to protocol sendmsg op.
Key data: socket lookup result, copied msghdr.
Transition: for AF_NETLINK sockets, dispatches to netlink_sendmsg.

3. [netlink_sendmsg](kernel/net6p8/net/netlink/af_netlink.c#L1826)
What it does: wraps payload into skb, sets netlink metadata (portid/group), unicasts to destination netlink endpoint.
Key data: skb payload, NETLINK_CB(skb).
Transition: netlink core receiver eventually invokes Generic Netlink receive path.

## 2) Generic Netlink dispatch

1. [genl_rcv](kernel/net6p8/net/netlink/genetlink.c#L1214)
What it does: Generic Netlink top-level receive callback from netlink_rcv_skb.
Key data: nlmsghdr inside skb.
Transition: calls genl_rcv_msg.

2. [genl_rcv_msg](kernel/net6p8/net/netlink/genetlink.c#L1197)
What it does: finds genl family by nlmsg_type and locks family op table.
Key data: family id -> family object mapping.
Transition: calls genl_family_rcv_msg.

3. [genl_family_rcv_msg_doit](kernel/net6p8/net/netlink/genetlink.c#L1080)
What it does: parses attributes, builds genl_info, executes selected op->doit handler.
Key data: parsed attrs array, genl_info.genlhdr->cmd.
Transition: invokes ethtool netlink doit function for CHANNELS_SET.

## 3) Ethtool CHANNELS_SET routing

1. [ETHTOOL_MSG_CHANNELS_SET registration](kernel/net6p8/net/ethtool/netlink.c#L924)
What it does: binds CHANNELS_SET message ID to default set handler and policy.
Key data: cmd=ETHTOOL_MSG_CHANNELS_SET, policy=ethnl_channels_set_policy.
Transition: request lands in ethnl_default_set_doit.

2. [ethnl_default_set_doit](kernel/net6p8/net/ethtool/netlink.c#L579)
What it does: common set-path wrapper for ethtool netlink operations; validates header, takes rtnl, calls request ops set callback.
Key data: req_info.dev, ops->set_validate, ops->set.
Transition: calls channels request ops set function.

3. [ethnl_set_channels](kernel/net6p8/net/ethtool/channels.c#L110)
What it does: parses requested channel counts and validates against max limits, RSS/RXFH/AF_XDP constraints.
Key data: ethtool_channels struct fields (combined/rx/tx/other).
Transition: calls driver set_channels callback.

4. [driver callback invocation dev->ethtool_ops->set_channels](kernel/net6p8/net/ethtool/channels.c#L195)
What it does: handoff from generic ethtool framework to NIC driver-specific implementation.
Key data: net_device->ethtool_ops table.
Transition: enters mlx5e_set_channels.

## 4) mlx5 ethtool callbacks

1. [netdev->ethtool_ops = &mlx5e_ethtool_ops](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L5140)
What it does: one-time registration of mlx5 ethtool handlers during netdev initialization.
Key data: function table pointer assignment.

2. [mlx5e_ethtool_ops.set_channels = mlx5e_set_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L2399)
What it does: maps set_channels op to mlx5 entry point.

3. [mlx5e_set_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L513)
What it does: small wrapper converting net_device to mlx5e_priv and calling main mlx5 implementation.
Transition: mlx5e_ethtool_set_channels.

4. [mlx5e_ethtool_set_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L432)
What it does: enforces mlx5 constraints (HTB, RSS contexts, MQPRIO), prepares new params, handles aRFS disable/enable around switch.
Key data: cur_params, new_params, state_lock, NETIF_F_NTUPLE.
Transition: calls mlx5e_safe_switch_params.

5. [new_params.num_channels = ch->combined_count](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L487)
What it does: maps ethtool combined queue count directly to mlx5 channel count target.
Key data: ch->combined_count (your example: 2).

6. [mlx5e_safe_switch_params call](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L496)
What it does: commits reconfiguration via safe two-phase reopen/swap logic.

## 5) Safe switch and channel set swap

1. [mlx5e_safe_switch_params](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3135)
What it does: if interface is opened, allocates new channel container and pre-opens new channels before swap.
Key data: reset flag, new_chs object.
Transition: mlx5e_open_channels then mlx5e_switch_priv_channels.

2. [mlx5e_open_channels for new channel set](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3154)
What it does: creates all channels/queues for new configuration in advance.

3. [mlx5e_switch_priv_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3092)
What it does: deactivates old channels, swaps priv->channels to new object, applies preactivate callback, then closes old channels.
Key data: old_chs/new_chs swap, carrier state handling.

4. [mlx5e_close_channels old set](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3121)
What it does: tears down old queue objects after successful swap.

5. [mlx5e_activate_priv_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3126)
What it does: enables new queues/NAPI and resumes traffic path.

## 6) Queue count and RSS/XPS updates

1. [mlx5e_num_channels_changed](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2956)
What it does: callback used during switch to sync netdev queue model and RSS for new channel count.

2. [mlx5e_update_netdev_queues](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2886)
What it does: updates TC mapping + real tx/rx queue counts atomically with rollback on failure.

3. [netif_set_real_num_tx_queues](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2879)
What it does: kernel-visible TX queue count update.

4. [netif_set_real_num_rx_queues](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2910)
What it does: kernel-visible RX queue count update.

5. [mlx5e_set_default_xps_cpumasks](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2965)
What it does: recomputes XPS cpumasks for updated channel layout.

6. [mlx5e_rx_res_rss_update_num_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2969)
What it does: updates RSS resource model to new channel count.

## 7) Per-channel reconstruction loop

1. [mlx5e_open_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2636)
What it does: allocates channel arrays and parameters for the target channel count.

2. [for each channel index i](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2654)
What it does: iterates channel creation exactly num_channels times (2 in your example).

3. [mlx5e_open_channel(priv, i, ...)](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2660)
What it does: builds one channel object and opens all associated queues.

## 8) Per-channel queue open order

1. [mlx5e_open_queues](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2345)
What it does: orchestrates queue bring-up order per channel.

2. [open CQs](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2355)
What it does: creates completion queues first so SQ/RQ can reference CQ numbers.

3. [open SQs](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2398)
What it does: creates TX send queues and associated state.

4. [open RXQ/RQ](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2402)
What it does: initializes RX queue state and creates receive queue object.

5. [mlx5e_open_rq(..., cpu_to_node(c->cpu), ...)](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2342)
What it does: binds RQ memory allocation policy to channel CPU NUMA node.
Key data: node parameter propagates into page_pool nid and queue allocations.

## 9) Driver create wrappers (build HW create payloads)

1. [mlx5e_create_cq](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2059)
What it does: fills create_cq_in payload (EQ number, page list, DB address) then calls core create.

2. [mlx5e_create_rq](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L1027)
What it does: fills create_rq_in payload (CQN, WQ, timestamp mode, PAS list) then calls core create.

3. [mlx5e_create_sq](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L1641)
What it does: fills create_sq_in payload (TIS, CQN, WQ settings, PAS list) then calls core create.

## 10) Core object creation and firmware opcodes

1. [mlx5_core_create_cq](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cq.c#L154)
What it does: validates CQ creation and normalizes command status.

2. [mlx5_create_cq sets CREATE_CQ and calls mlx5_cmd_do](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cq.c#L103)
What it does: stamps opcode MLX5_CMD_OP_CREATE_CQ and submits command to FW path.

3. [mlx5_core_create_rq sets CREATE_RQ and calls mlx5_cmd_exec](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/transobj.c#L66)
What it does: stamps MLX5_CMD_OP_CREATE_RQ and submits to firmware.

4. [mlx5_core_create_sq sets CREATE_SQ and calls mlx5_cmd_exec](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/transobj.c#L110)
What it does: stamps MLX5_CMD_OP_CREATE_SQ and submits to firmware.

## 11) Firmware command engine

1. [mlx5_cmd_exec](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cmd.c#L2004)
What it does: high-level synchronous FW command API with status checks.

2. [mlx5_cmd_do](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cmd.c#L1982)
What it does: low-level submit/wait path (cmd_exec), parses opcode/op_mod, returns command status mapping.

## 12) Live trace scripts for this flow

1. [trace_mlx5_ethtool_channels_live.bt](gnr_nic_perf/260408/trace_mlx5_ethtool_channels_live.bt)
What it provides: runtime EVT timeline across ethtool -> mlx5 switch -> queue create functions.

2. [run_trace_mlx5_ethtool_channels_live.sh](gnr_nic_perf/260408/run_trace_mlx5_ethtool_channels_live.sh)
What it provides: one-command capture wrapper and log output in your workspace.

## 13) Quick verification checklist (during one ethtool -L run)

1. You should see stage=ethnl_set_channels and stage=mlx5e_set_channels.
2. You should see stage=mlx5e_safe_switch_params with new_num_channels=2.
3. You should see repeated stage=mlx5e_open_channel for ix=0 and ix=1.
4. You should see stage=mlx5_core_create_cq_ret, stage=mlx5_core_create_rq_ret, and stage=mlx5_core_create_sq_ret with ret=0.

## 14) Refined Narrative With Clickable Function Links

For ethtool -L ens7f0np0 combined 2 on mlx5, this is the kernel path from syscall to hardware programming.

Userspace enters the syscall layer at [sendmsg syscall entry](kernel/net6p8/net/socket.c#L2674), then into [__sys_sendmsg](kernel/net6p8/net/socket.c#L2653). For Generic Netlink sockets, the kernel send path goes through [netlink_sendmsg](kernel/net6p8/net/netlink/af_netlink.c#L1826).

Netlink dispatch reaches Generic Netlink core. Generic Netlink receive callback uses [genl_rcv](kernel/net6p8/net/netlink/genetlink.c#L1214). It dispatches requests through [genl_rcv_msg](kernel/net6p8/net/netlink/genetlink.c#L1197), then doit handling at [genl_family_rcv_msg_doit](kernel/net6p8/net/netlink/genetlink.c#L1080).

Ethtool Generic Netlink handler for CHANNELS_SET is selected. Command registration for CHANNELS_SET is [ETHTOOL_MSG_CHANNELS_SET registration](kernel/net6p8/net/ethtool/netlink.c#L924). Default set handler is [ethnl_default_set_doit](kernel/net6p8/net/ethtool/netlink.c#L579). It calls per-request set callback at [ops->set call site](kernel/net6p8/net/ethtool/netlink.c#L610).

Ethtool channels set logic validates and calls driver callback. CHANNELS_SET policy and handler are in [channels set policy](kernel/net6p8/net/ethtool/channels.c#L91) and [ethnl_set_channels](kernel/net6p8/net/ethtool/channels.c#L110). combined_count is parsed at [combined_count parse](kernel/net6p8/net/ethtool/channels.c#L131). Driver call happens at [dev->ethtool_ops->set_channels invocation](kernel/net6p8/net/ethtool/channels.c#L195), which is dev->ethtool_ops->set_channels.

mlx5 ethtool callback receives combined 2 and starts channel switch. mlx5 callback registration is [mlx5e_ethtool_ops set_channels entry](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L2399). net_device hooks mlx5 ethtool ops at [netdev ethtool_ops assignment](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L5140). set handler is [mlx5e_set_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L513). combined_count is copied to new_params.num_channels at [new_params assignment](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L487). switch and reopen are triggered by [mlx5e_safe_switch_params call](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_ethtool.c#L496).

mlx5 safe switch path builds new channel set and swaps. safe switch entry is [mlx5e_safe_switch_params](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3135). New channels are opened first at [mlx5e_open_channels call for new set](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3154). Then old and new swap is done in [mlx5e_switch_priv_channels](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3092), with old channels closed at [mlx5e_close_channels old set](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L3121). For value 2, open loop runs i = 0..1 in [channel open loop](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2654).

Linux netdev queue counts are updated to match new channel count. preactivate callback updates netdev queues at [mlx5e_num_channels_changed](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2956). TX queue count update is at [netif_set_real_num_tx_queues path](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2879). RX queue count update via netif_set_real_num_rx_queues is at [netif_set_real_num_rx_queues path](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2910).

Per-channel queue objects are opened and programmed. Queue open sequence starts in [mlx5e_open_queues](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2345). CQ open path calls create CQ in [mlx5e_create_cq](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2059). SQ open path eventually calls create SQ in [mlx5e_create_sq](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L1641). RQ open path goes through [mlx5e_open_rq call with cpu_to_node(c->cpu)](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L2342) and create RQ at [mlx5e_create_rq](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/en_main.c#L1027).

Hardware and firmware command submission points are next. RQ create opcode and FW exec are in [mlx5_core_create_rq opcode set](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/transobj.c#L71) and [mlx5_core_create_rq fw exec](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/transobj.c#L72). SQ create opcode and FW exec are in [mlx5_core_create_sq opcode set](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/transobj.c#L115) and [mlx5_core_create_sq fw exec](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/transobj.c#L116). CQ create opcode and FW exec are in [mlx5_create_cq opcode set](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cq.c#L103) and [mlx5_create_cq fw exec](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cq.c#L104). FW command engine entry is [mlx5_cmd_exec](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cmd.c#L2004), calling [mlx5_cmd_do](kernel/net6p8/drivers/net/ethernet/mellanox/mlx5/core/cmd.c#L1982).

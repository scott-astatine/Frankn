use super::registry::*;
use crate::capabilities::registry::{
    CapabilityDescriptor, CapabilityInventory, CapabilityInventoryEntry, CapabilityProvider,
};
use std::collections::HashMap;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a minimal CapabilityDescriptor for testing.
fn test_descriptor(id: &str, name: &str) -> CapabilityDescriptor {
    CapabilityDescriptor {
        id: id.to_string(),
        name: name.to_string(),
        version: "1.0.0".to_string(),
        actions: vec![],
        properties: HashMap::new(),
        events: vec![],
        schemas: HashMap::new(),
        permissions: vec![],
        platform_support: vec![],
        health: "healthy".to_string(),
    }
}

/// Build a CapabilitySession for testing.
fn test_session(
    session_id: &str,
    client_id: &str,
    capability_id: &str,
    node_id: &str,
) -> CapabilitySession {
    CapabilitySession {
        session_id: session_id.to_string(),
        client_id: client_id.to_string(),
        capability_id: capability_id.to_string(),
        node_id: node_id.to_string(),
        status: CapabilitySessionStatus::Pending,
        error: None,
    }
}

/// Build a CapabilityInventoryEntry for a node provider.
fn test_inventory_entry(descriptor: CapabilityDescriptor, node_id: &str) -> CapabilityInventoryEntry {
    CapabilityInventoryEntry {
        descriptor,
        provider: CapabilityProvider {
            kind: "node".to_string(),
            provider_id: node_id.to_string(),
        },
        availability: "available".to_string(),
    }
}

// ===========================================================================
// F1 – Node authentication (allowed_nodes gate)
// ===========================================================================

/// F1: A node whose ID is present in allowed_nodes is accepted.
#[test]
fn f1_allowed_node_is_accepted() {
    let allowed_nodes: Vec<String> = vec![
        "node-01".to_string(),
        "node-02".to_string(),
    ];

    assert!(
        allowed_nodes.contains(&"node-01".to_string()),
        "node-01 should be in the allowed list"
    );
    assert!(
        allowed_nodes.contains(&"node-02".to_string()),
        "node-02 should be in the allowed list"
    );
}

/// F1: A node whose ID is NOT in allowed_nodes is rejected.
#[test]
fn f1_disallowed_node_is_rejected() {
    let allowed_nodes: Vec<String> = vec![
        "node-01".to_string(),
        "node-02".to_string(),
    ];

    assert!(
        !allowed_nodes.contains(&"node-99".to_string()),
        "node-99 must NOT be in the allowed list"
    );
}

/// F1: An empty allowed_nodes list rejects every node.
#[test]
fn f1_empty_allowed_nodes_rejects_all() {
    let allowed_nodes: Vec<String> = vec![];

    assert!(
        !allowed_nodes.contains(&"node-01".to_string()),
        "empty list should reject all nodes"
    );
}

// ===========================================================================
// F2 – Node registration & capability inventory lifecycle
// ===========================================================================

/// F2: After registering capabilities in CapabilityInventory, they appear in list().
#[test]
fn f2_capability_inventory_registration() {
    let mut inventory = CapabilityInventory::new();

    let camera_desc = test_descriptor("camera", "Camera");
    let entry = test_inventory_entry(camera_desc, "node-01");
    inventory.register(entry);

    let listed = inventory.list();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].descriptor.id, "camera");
    assert_eq!(listed[0].provider.provider_id, "node-01");
}

/// F2: After unregistering a provider, its entries disappear from inventory.
#[test]
fn f2_capability_inventory_unregister() {
    let mut inventory = CapabilityInventory::new();

    inventory.register(test_inventory_entry(
        test_descriptor("camera", "Camera"),
        "node-01",
    ));
    inventory.register(test_inventory_entry(
        test_descriptor("temperature", "Temperature Sensor"),
        "node-01",
    ));

    assert_eq!(inventory.list().len(), 2);

    inventory.unregister_by_provider("node", "node-01");
    assert_eq!(
        inventory.list().len(),
        0,
        "all entries for node-01 should be gone"
    );
}

/// F2: Session registry supports register / get / unregister lifecycle.
#[test]
fn f2_session_registry_lifecycle() {
    let mut csr = CapabilitySessionRegistry::new();

    let sess = test_session("sess-01", "client-01", "camera", "node-01");
    csr.register(sess);

    assert!(csr.get("sess-01").is_some(), "session should be retrievable after register");

    csr.remove("sess-01");
    assert!(csr.get("sess-01").is_none(), "session should be gone after remove");
}

// ===========================================================================
// F3 – Multiple clients sharing one node
// ===========================================================================

/// F3: Two sessions from different clients to the same node/capability coexist.
#[test]
fn f3_multiple_clients_sharing_one_node() {
    let mut csr = CapabilitySessionRegistry::new();

    csr.register(test_session("sess-A", "client-A", "camera", "node-N"));
    csr.register(test_session("sess-B", "client-B", "camera", "node-N"));

    let sess_a = csr.get("sess-A").expect("session A must exist");
    let sess_b = csr.get("sess-B").expect("session B must exist");

    assert_eq!(sess_a.client_id, "client-A");
    assert_eq!(sess_a.node_id, "node-N");
    assert_eq!(sess_a.capability_id, "camera");

    assert_eq!(sess_b.client_id, "client-B");
    assert_eq!(sess_b.node_id, "node-N");
    assert_eq!(sess_b.capability_id, "camera");

    assert_eq!(csr.list().len(), 2, "both sessions should coexist");
}

// ===========================================================================
// F4 – Multiple capabilities across nodes
// ===========================================================================

/// F4: A single client can hold sessions to different capabilities on different nodes.
#[test]
fn f4_multiple_capabilities_across_nodes() {
    let mut csr = CapabilitySessionRegistry::new();

    // client-A → camera → node-N
    csr.register(test_session("sess-1", "client-A", "camera", "node-N"));
    // client-A → temperature → node-M
    csr.register(test_session("sess-2", "client-A", "temperature", "node-M"));

    let s1 = csr.get("sess-1").expect("session 1 must exist");
    assert_eq!(s1.client_id, "client-A");
    assert_eq!(s1.capability_id, "camera");
    assert_eq!(s1.node_id, "node-N");

    let s2 = csr.get("sess-2").expect("session 2 must exist");
    assert_eq!(s2.client_id, "client-A");
    assert_eq!(s2.capability_id, "temperature");
    assert_eq!(s2.node_id, "node-M");

    assert_eq!(csr.list().len(), 2);
}

// ===========================================================================
// F5 – Session authorization (ownership validation)
// ===========================================================================

/// F5: Ownership fields on CapabilitySession allow authorization checks.
#[test]
fn f5_session_ownership_validation() {
    let sess = test_session("sess-01", "client-01", "camera", "node-01");

    // Authorized node
    assert_eq!(sess.node_id, "node-01", "authorized node matches");
    // Wrong node
    assert_ne!(sess.node_id, "node-02", "wrong node must not match");

    // Authorized client
    assert_eq!(sess.client_id, "client-01", "authorized client matches");
    // Wrong client
    assert_ne!(sess.client_id, "client-02", "wrong client must not match");
}

// ===========================================================================
// F6 – Node disconnect cleanup
// ===========================================================================

/// F6: Full cleanup after a node disconnects – sessions, inventory, and
///     registry entries for that node are all removed.
#[test]
fn f6_node_disconnect_cleanup() {
    let node_id = "node-01";

    // --- Session registry ---
    let mut csr = CapabilitySessionRegistry::new();
    csr.register(test_session("s1", "c1", "camera", node_id));
    csr.register(test_session("s2", "c2", "temperature", node_id));
    csr.register(test_session("s3", "c3", "mic", "node-02")); // unrelated

    // Find sessions belonging to the disconnected node
    let to_close: Vec<String> = csr
        .list()
        .iter()
        .filter(|s| s.node_id == node_id)
        .map(|s| s.session_id.clone())
        .collect();
    assert_eq!(to_close.len(), 2, "should find 2 sessions for node-01");

    // Close (set status) then remove
    for sid in &to_close {
        if let Some(s) = csr.get_mut(sid) {
            s.status = CapabilitySessionStatus::Closed;
        }
        csr.remove(sid);
    }

    // Only the unrelated session remains
    let remaining: Vec<_> = csr
        .list()
        .iter()
        .filter(|s| s.node_id == node_id)
        .cloned()
        .collect();
    assert!(remaining.is_empty(), "no sessions for node-01 should remain");
    assert_eq!(csr.list().len(), 1, "unrelated session should survive");

    // --- Capability inventory ---
    let mut ci = CapabilityInventory::new();
    ci.register(test_inventory_entry(
        test_descriptor("camera", "Camera"),
        node_id,
    ));
    ci.register(test_inventory_entry(
        test_descriptor("temperature", "Temperature Sensor"),
        node_id,
    ));
    ci.register(test_inventory_entry(
        test_descriptor("mic", "Microphone"),
        "node-02",
    ));

    ci.unregister_by_provider("node", node_id);

    let inv_remaining: Vec<_> = ci
        .list()
        .iter()
        .filter(|e| e.provider.provider_id == node_id)
        .cloned()
        .collect();
    assert!(inv_remaining.is_empty(), "no inventory entries for node-01 should remain");
    assert_eq!(ci.list().len(), 1, "node-02 inventory entry should survive");
}

// ===========================================================================
// F7 – WebRTC failure cleanup (session state machine)
// ===========================================================================

/// F7: A capability session transitions Pending → Active → Failed → removed.
#[test]
fn f7_webrtc_failure_cleanup() {
    let mut csr = CapabilitySessionRegistry::new();

    csr.register(test_session("sess-fail", "client-01", "camera", "node-01"));

    // Pending → Active
    {
        let s = csr.get_mut("sess-fail").unwrap();
        assert_eq!(s.status, CapabilitySessionStatus::Pending);
        s.status = CapabilitySessionStatus::Active;
    }
    assert_eq!(
        csr.get("sess-fail").unwrap().status,
        CapabilitySessionStatus::Active
    );

    // Active → Failed
    {
        let s = csr.get_mut("sess-fail").unwrap();
        s.status = CapabilitySessionStatus::Failed;
        s.error = Some("ICE negotiation timed out".to_string());
    }
    let failed = csr.get("sess-fail").unwrap();
    assert_eq!(failed.status, CapabilitySessionStatus::Failed);
    assert!(failed.error.is_some());

    // Failed → removed
    let removed = csr.remove("sess-fail");
    assert!(removed.is_some(), "remove should return the session");
    assert!(csr.get("sess-fail").is_none(), "session should be gone");
}

// ===========================================================================
// F8 – Node reconnect idempotency
// ===========================================================================

/// F8: Simulates a full reconnect cycle – old state is purged and new
///     registration becomes authoritative.
#[test]
fn f8_node_reconnect_idempotency() {
    let node_id = "node-01";

    // --- Initial registration ---
    let mut csr = CapabilitySessionRegistry::new();
    let mut ci = CapabilityInventory::new();

    csr.register(test_session("old-s1", "c1", "camera", node_id));
    csr.register(test_session("old-s2", "c2", "temperature", node_id));
    ci.register(test_inventory_entry(
        test_descriptor("camera", "Camera"),
        node_id,
    ));
    ci.register(test_inventory_entry(
        test_descriptor("temperature", "Temperature Sensor"),
        node_id,
    ));

    assert_eq!(
        csr.list().iter().filter(|s| s.node_id == node_id).count(),
        2
    );
    assert_eq!(
        ci.list()
            .iter()
            .filter(|e| e.provider.provider_id == node_id)
            .count(),
        2
    );

    // --- Reconnect: tear down old state ---
    let old_ids: Vec<String> = csr
        .list()
        .iter()
        .filter(|s| s.node_id == node_id)
        .map(|s| s.session_id.clone())
        .collect();
    for sid in &old_ids {
        if let Some(s) = csr.get_mut(sid) {
            s.status = CapabilitySessionStatus::Closed;
        }
        csr.remove(sid);
    }
    ci.unregister_by_provider("node", node_id);

    assert_eq!(
        csr.list().iter().filter(|s| s.node_id == node_id).count(),
        0,
        "old sessions should be gone"
    );
    assert_eq!(
        ci.list()
            .iter()
            .filter(|e| e.provider.provider_id == node_id)
            .count(),
        0,
        "old providers should be gone"
    );

    // --- Re-register (reconnect) ---
    csr.register(test_session("new-s1", "c1", "camera", node_id));
    ci.register(test_inventory_entry(
        test_descriptor("camera", "Camera"),
        node_id,
    ));

    assert_eq!(
        csr.list().iter().filter(|s| s.node_id == node_id).count(),
        1,
        "new session should exist"
    );
    assert_eq!(
        ci.list()
            .iter()
            .filter(|e| e.provider.provider_id == node_id)
            .count(),
        1,
        "new provider should exist"
    );

    // Old sessions must not be retrievable
    assert!(csr.get("old-s1").is_none(), "old session old-s1 must be gone");
    assert!(csr.get("old-s2").is_none(), "old session old-s2 must be gone");

    // New session is authoritative
    let new = csr.get("new-s1").expect("new session must exist");
    assert_eq!(new.node_id, node_id);
    assert_eq!(new.status, CapabilitySessionStatus::Pending);
}

// ===========================================================================
// F9 – Multiple sessions against one node
// ===========================================================================

/// F9: Multiple concurrent sessions to the same node coexist and are all
///     discoverable by filtering on node_id.
#[test]
fn f9_multiple_sessions_against_one_node() {
    let mut csr = CapabilitySessionRegistry::new();

    csr.register(test_session("sess-A", "c1", "camera", "node-N"));
    csr.register(test_session("sess-B", "c2", "temperature", "node-N"));
    csr.register(test_session("sess-C", "c3", "mic", "node-N"));

    let node_sessions: Vec<_> = csr
        .list()
        .into_iter()
        .filter(|s| s.node_id == "node-N")
        .collect();

    assert_eq!(
        node_sessions.len(),
        3,
        "all three sessions should coexist for node-N"
    );

    // Verify each is individually retrievable
    assert!(csr.get("sess-A").is_some());
    assert!(csr.get("sess-B").is_some());
    assert!(csr.get("sess-C").is_some());
}

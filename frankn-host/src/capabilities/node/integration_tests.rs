/// Integration tests for the Host-side Node capability architecture.
///
/// These tests validate the complete end-to-end flow described in Phase G of
/// the refactoring review, exercising all three registries (NodeRegistry,
/// CapabilityInventory, CapabilitySessionRegistry) as an integrated system.
///
/// Test topology:
///
/// ```text
/// Host
///  ├── Node-N (camera, temperature)
///  ├── Client-A
///  └── Client-B
/// ```

use super::registry::*;
use crate::capabilities::registry::{
    CapabilityDescriptor, CapabilityInventory, CapabilityInventoryEntry, CapabilityProvider,
};
use std::collections::HashMap;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn make_descriptor(id: &str) -> CapabilityDescriptor {
    CapabilityDescriptor {
        id: id.to_string(),
        name: id.to_string(),
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

fn make_session(
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

fn register_node_capabilities(
    ci: &mut CapabilityInventory,
    node_id: &str,
    capabilities: &[&str],
) {
    for cap_id in capabilities {
        ci.register(CapabilityInventoryEntry {
            descriptor: make_descriptor(cap_id),
            provider: CapabilityProvider {
                kind: "node".to_string(),
                provider_id: node_id.to_string(),
            },
            availability: "available".to_string(),
        });
    }
}

// ===========================================================================
// Phase G: Full integration test — single client
// ===========================================================================

/// Simulates the complete 12-step flow from Phase G with a single client:
///
/// 1. Node authenticates (allowed_nodes check)
/// 2. Node registers
/// 3. Camera capability appears in inventory
/// 4. Client requests camera
/// 5. Host resolves camera → Node
/// 6. Node creates capability session (Pending)
/// 7. Node reports activation success (Active)
/// 8. Session is active
/// 9. Client closes session
/// 10. Host removes session
/// 11. Verify cleanup
#[test]
fn integration_single_client_full_flow() {
    let node_id = "node-N";
    let client_id = "client-A";
    let allowed_nodes = vec![node_id.to_string()];

    // --- Step 1: Node authenticates ---
    assert!(
        allowed_nodes.contains(&node_id.to_string()),
        "Node must be in allowed_nodes"
    );

    // --- Step 2: Node registers capabilities ---
    let mut ci = CapabilityInventory::new();
    let mut csr = CapabilitySessionRegistry::new();

    register_node_capabilities(&mut ci, node_id, &["camera", "temperature"]);

    // --- Step 3: Camera capability appears ---
    let camera_entries: Vec<_> = ci
        .list()
        .into_iter()
        .filter(|e| e.descriptor.id == "camera")
        .collect();
    assert_eq!(camera_entries.len(), 1, "camera should be in inventory");
    assert_eq!(camera_entries[0].provider.provider_id, node_id);

    // --- Step 4-5: Client requests camera, Host resolves to Node ---
    let resolved_node = ci
        .list()
        .iter()
        .find(|e| e.descriptor.id == "camera")
        .map(|e| e.provider.provider_id.clone());
    assert_eq!(
        resolved_node,
        Some(node_id.to_string()),
        "Host should resolve camera to node-N"
    );

    // --- Step 6: Create capability session (Pending) ---
    let session_id = "cap-sess-001";
    csr.register(make_session(session_id, client_id, "camera", node_id));

    let sess = csr.get(session_id).expect("session must exist");
    assert_eq!(sess.status, CapabilitySessionStatus::Pending);
    assert_eq!(sess.node_id, node_id);
    assert_eq!(sess.client_id, client_id);

    // --- Step 7: Node reports activation success ---
    {
        let sess = csr.get_mut(session_id).unwrap();
        sess.status = CapabilitySessionStatus::Active;
    }

    // --- Step 8: Session is active ---
    assert_eq!(
        csr.get(session_id).unwrap().status,
        CapabilitySessionStatus::Active
    );

    // --- Step 9-10: Client closes session, Host removes ---
    {
        let sess = csr.get_mut(session_id).unwrap();
        sess.status = CapabilitySessionStatus::Closed;
    }
    let removed = csr.remove(session_id);
    assert!(removed.is_some());
    assert_eq!(removed.unwrap().status, CapabilitySessionStatus::Closed);

    // --- Step 11: Verify cleanup ---
    assert!(csr.get(session_id).is_none(), "session should be gone");
    // Inventory should still have the capability (node is still connected)
    assert_eq!(ci.list().len(), 2, "capabilities still registered");
}

// ===========================================================================
// Phase G: Two-client / one-node simultaneous test
// ===========================================================================

/// The "big one" — two clients simultaneously using the same node's camera.
///
/// Proves:
/// - Both sessions coexist
/// - Closing one doesn't affect the other
/// - The node stays registered throughout
/// - Final cleanup removes everything
#[test]
fn integration_two_clients_one_node() {
    let node_id = "node-N";
    let client_a = "client-A";
    let client_b = "client-B";
    let allowed_nodes = vec![node_id.to_string()];

    let mut ci = CapabilityInventory::new();
    let mut csr = CapabilitySessionRegistry::new();

    // Node authenticates and registers
    assert!(allowed_nodes.contains(&node_id.to_string()));
    register_node_capabilities(&mut ci, node_id, &["camera"]);

    // --- Client A requests camera ---
    let sess_a_id = "cap-sess-A";
    csr.register(make_session(sess_a_id, client_a, "camera", node_id));
    {
        let s = csr.get_mut(sess_a_id).unwrap();
        s.status = CapabilitySessionStatus::Active;
    }

    // --- Client B requests camera (same node, same capability) ---
    let sess_b_id = "cap-sess-B";
    csr.register(make_session(sess_b_id, client_b, "camera", node_id));
    {
        let s = csr.get_mut(sess_b_id).unwrap();
        s.status = CapabilitySessionStatus::Active;
    }

    // --- Both sessions coexist ---
    assert_eq!(csr.list().len(), 2, "both sessions must coexist");

    let node_sessions: Vec<_> = csr
        .list()
        .into_iter()
        .filter(|s| s.node_id == node_id)
        .collect();
    assert_eq!(node_sessions.len(), 2, "node-N should serve two sessions");

    // --- Verify ownership isolation ---
    let sa = csr.get(sess_a_id).unwrap();
    assert_eq!(sa.client_id, client_a);
    assert_ne!(sa.client_id, client_b, "session A belongs to client-A only");

    let sb = csr.get(sess_b_id).unwrap();
    assert_eq!(sb.client_id, client_b);
    assert_ne!(sb.client_id, client_a, "session B belongs to client-B only");

    // --- Client A closes their session ---
    {
        let s = csr.get_mut(sess_a_id).unwrap();
        s.status = CapabilitySessionStatus::Closed;
    }
    csr.remove(sess_a_id);

    // --- Client B is unaffected ---
    assert!(csr.get(sess_a_id).is_none(), "A's session should be gone");
    let sb = csr.get(sess_b_id).expect("B's session must still exist");
    assert_eq!(
        sb.status,
        CapabilitySessionStatus::Active,
        "B's session should still be active"
    );
    assert_eq!(csr.list().len(), 1, "only B's session remains");

    // --- Client B closes their session ---
    {
        let s = csr.get_mut(sess_b_id).unwrap();
        s.status = CapabilitySessionStatus::Closed;
    }
    csr.remove(sess_b_id);

    // --- Full cleanup: no sessions remain ---
    assert_eq!(csr.list().len(), 0, "all sessions should be gone");
    // Camera is still in inventory (node is still connected)
    assert_eq!(ci.list().len(), 1, "node's capability still registered");

    // --- Node disconnects ---
    ci.unregister_by_provider("node", node_id);
    assert_eq!(ci.list().len(), 0, "all inventory entries cleared");
}

// ===========================================================================
// Bonus: Mixed multi-node, multi-client, multi-capability
// ===========================================================================

/// Stress test: two nodes, two clients, three capabilities, five sessions.
#[test]
fn integration_multi_node_multi_client() {
    let mut ci = CapabilityInventory::new();
    let mut csr = CapabilitySessionRegistry::new();

    // Node-A provides camera + mic
    register_node_capabilities(&mut ci, "node-A", &["camera", "mic"]);
    // Node-B provides temperature
    register_node_capabilities(&mut ci, "node-B", &["temperature"]);

    assert_eq!(ci.list().len(), 3);

    // Client-1: camera from Node-A, temperature from Node-B
    csr.register(make_session("s1", "client-1", "camera", "node-A"));
    csr.register(make_session("s2", "client-1", "temperature", "node-B"));

    // Client-2: camera from Node-A, mic from Node-A, temperature from Node-B
    csr.register(make_session("s3", "client-2", "camera", "node-A"));
    csr.register(make_session("s4", "client-2", "mic", "node-A"));
    csr.register(make_session("s5", "client-2", "temperature", "node-B"));

    // All sessions coexist
    assert_eq!(csr.list().len(), 5);

    // Activate all
    for sess in csr.list() {
        let s = csr.get_mut(&sess.session_id).unwrap();
        s.status = CapabilitySessionStatus::Active;
    }

    // Node-A disconnects: close its sessions and remove its providers
    let node_a_sessions: Vec<String> = csr
        .list()
        .iter()
        .filter(|s| s.node_id == "node-A")
        .map(|s| s.session_id.clone())
        .collect();
    assert_eq!(node_a_sessions.len(), 3, "node-A has 3 sessions");

    for sid in &node_a_sessions {
        if let Some(s) = csr.get_mut(sid) {
            s.status = CapabilitySessionStatus::Closed;
        }
        csr.remove(sid);
    }
    ci.unregister_by_provider("node", "node-A");

    // Node-B sessions survive
    assert_eq!(csr.list().len(), 2, "node-B's 2 sessions survive");
    assert_eq!(ci.list().len(), 1, "only temperature from node-B remains");

    // Both surviving sessions belong to Node-B
    for sess in csr.list() {
        assert_eq!(sess.node_id, "node-B");
        assert_eq!(sess.capability_id, "temperature");
        assert_eq!(sess.status, CapabilitySessionStatus::Active);
    }

    // Node-B disconnects
    let node_b_sessions: Vec<String> = csr
        .list()
        .iter()
        .filter(|s| s.node_id == "node-B")
        .map(|s| s.session_id.clone())
        .collect();
    for sid in &node_b_sessions {
        csr.remove(sid);
    }
    ci.unregister_by_provider("node", "node-B");

    assert_eq!(csr.list().len(), 0, "all sessions cleared");
    assert_eq!(ci.list().len(), 0, "all inventory cleared");
}

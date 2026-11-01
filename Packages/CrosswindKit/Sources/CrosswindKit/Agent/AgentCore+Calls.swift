// SPDX-License-Identifier: AGPL-3.0-or-later
import Foundation

/// Guest-initiated calls for `AgentCore`: each one passes `GuestCallGate`, then goes to the stub of its app or is
/// answered by the agent (links, clipboard reads). Split out of AgentCore.swift to keep that file within lint limits.
extension AgentCore {
    /// Calls go to the stub of the app that triggered them; links open straight away. Every call first passes the
    /// gate, which enforces the per-app limits and trims fields.
    func route(call received: Crosswind_Control_Call) {
        let call: Crosswind_Control_Call
        switch gate.admit(received) {
        case .reject(let reason):
            return replyToCall(received.id, error: reason)
        case .admit(let admitted):
            call = admitted
        }
        if case .clipboardRead(let read)? = call.body { return clipboard.read(callID: call.id, mime: read.mime) }
        if case .openURL(let open)? = call.body {
            let ok = URL(string: open.url).map(openURL) ?? false
            if ok {
                controlToGuest?.send(
                    .with {
                        $0.callReply = .with {
                            $0.id = call.id
                            $0.ok = .init()
                        }
                    })
            } else {
                replyToCall(call.id, error: "cannot open this link")
            }
        } else if let stub = stubs[call.appID] {
            stub.connection.send(.with { $0.guest = .with { $0.call = call } })
        } else {
            gate.finished(call: call.id)
            replyToCall(call.id, error: "\(call.appID) has no open window to ask")
        }
    }

    private func replyToCall(_ id: UInt64, error: String) {
        controlToGuest?.send(
            .with {
                $0.callReply = .with {
                    $0.id = id
                    $0.error = .with { $0.message = error }
                }
            })
    }
}

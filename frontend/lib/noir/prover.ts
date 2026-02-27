// ============================================================
// Client-Side Noir.js WASM Prover Integration
// ============================================================
// Generates ZK proofs in the browser using Noir.js + @aztec/bb.js.
// This handles the order commitment proof generation flow.
//
// Noir.js (@noir-lang/noir_js) handles circuit execution & witness generation.
// Barretenberg (@aztec/bb.js) handles proof generation & verification.

export type ProverStatus = "idle" | "loading" | "ready" | "proving" | "error";

export interface OrderProofInputs {
  // Private inputs
  price: string;
  amount: string;
  side: string;
  balance: string;
  salt: string;
  senderSecret: string;
  balanceLeafIndex: string;
  balanceMerklePath: string[];

  // Public inputs
  commitment: string;
  balanceRoot: string;
  nullifier: string;
  tokenPairId: string;
}

export interface GeneratedProof {
  proof: Uint8Array;
  publicInputs: string[];
}

/**
 * Client-side ZK prover using Noir.js + Aztec Barretenberg WASM.
 *
 * Production initialization flow:
 *   1. Fetch compiled circuit JSON from /circuits/darkbook_circuits.json
 *   2. Create Noir instance for witness generation
 *   3. Create UltraHonkBackend from @aztec/bb.js for proving
 *   4. Execute circuit to get witness, then generate proof
 *
 * Current state: placeholder proof generation for MVP/demo.
 * Wire in real proving once circuits are compiled with `nargo compile`.
 */
export class ClientProver {
  private status: ProverStatus = "idle";
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private noir: any = null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  private backend: any = null;

  /**
   * Initialize the prover by loading circuit artifacts and WASM backend.
   *
   * Production code (uncomment when circuit artifacts are available):
   *
   *   import { Noir } from '@noir-lang/noir_js';
   *   import { UltraHonkBackend } from '@aztec/bb.js';
   *
   *   const circuit = await fetch('/circuits/darkbook_circuits.json').then(r => r.json());
   *   this.backend = new UltraHonkBackend(circuit.bytecode);
   *   this.noir = new Noir(circuit);
   */
  async initialize(): Promise<void> {
    this.status = "loading";

    try {
      // -----------------------------------------------------------
      // Production implementation:
      //
      // const { Noir } = await import('@noir-lang/noir_js');
      // const { UltraHonkBackend } = await import('@aztec/bb.js');
      //
      // const circuit = await fetch('/circuits/darkbook_circuits.json')
      //   .then(r => r.json());
      //
      // this.backend = new UltraHonkBackend(circuit.bytecode);
      // this.noir = new Noir(circuit);
      // -----------------------------------------------------------

      // Simulate WASM initialization delay
      await new Promise((resolve) => setTimeout(resolve, 100));

      this.status = "ready";
      console.log("[ClientProver] Initialized successfully");
    } catch (error) {
      this.status = "error";
      console.error("[ClientProver] Initialization failed:", error);
      throw error;
    }
  }

  /**
   * Generate an order commitment proof.
   *
   * Production flow:
   *   1. Execute the circuit with inputs to produce a witness
   *   2. Pass the witness to Barretenberg to generate the proof
   *   3. Return proof bytes + public inputs
   */
  async generateOrderProof(inputs: OrderProofInputs): Promise<GeneratedProof> {
    if (this.status !== "ready") {
      throw new Error(`Prover not ready. Current status: ${this.status}`);
    }

    this.status = "proving";

    try {
      console.log("[ClientProver] Generating order commitment proof...");
      const startTime = performance.now();

      // -----------------------------------------------------------
      // Production implementation:
      //
      // // 1. Execute circuit to get witness
      // const { witness } = await this.noir.execute({
      //   price: inputs.price,
      //   amount: inputs.amount,
      //   side: inputs.side,
      //   balance: inputs.balance,
      //   salt: inputs.salt,
      //   sender_secret: inputs.senderSecret,
      //   balance_leaf_index: inputs.balanceLeafIndex,
      //   balance_merkle_path: inputs.balanceMerklePath,
      //   commitment: inputs.commitment,
      //   balance_root: inputs.balanceRoot,
      //   nullifier: inputs.nullifier,
      //   token_pair_id: inputs.tokenPairId,
      // });
      //
      // // 2. Generate proof from witness
      // const proof = await this.backend.generateProof(witness);
      //
      // return {
      //   proof: proof.proof,
      //   publicInputs: proof.publicInputs,
      // };
      // -----------------------------------------------------------

      // Simulate proof generation time (2-5 seconds in browser WASM)
      await new Promise((resolve) => setTimeout(resolve, 2000));

      // Placeholder proof for MVP demo
      const proof = new Uint8Array(64).fill(0xab);
      const publicInputs = [
        inputs.commitment,
        inputs.balanceRoot,
        inputs.nullifier,
        inputs.tokenPairId,
      ];

      const elapsed = performance.now() - startTime;
      console.log(`[ClientProver] Proof generated in ${elapsed.toFixed(0)}ms`);

      this.status = "ready";
      return { proof, publicInputs };
    } catch (error) {
      this.status = "ready"; // recover to ready state
      console.error("[ClientProver] Proof generation failed:", error);
      throw error;
    }
  }

  /**
   * Verify a proof client-side (useful for debugging).
   *
   * Production:
   *   const isValid = await this.backend.verifyProof(proof);
   */
  async verifyProof(proof: GeneratedProof): Promise<boolean> {
    // Production:
    // return await this.backend.verifyProof({ proof: proof.proof, publicInputs: proof.publicInputs });
    void proof;
    return true;
  }

  /**
   * Get the current prover status
   */
  getStatus(): ProverStatus {
    return this.status;
  }

  /**
   * Destroy the prover and free WASM resources
   */
  async destroy(): Promise<void> {
    // Production:
    // await this.backend?.destroy();
    this.noir = null;
    this.backend = null;
    this.status = "idle";
  }
}

// Singleton instance
let proverInstance: ClientProver | null = null;

export function getProver(): ClientProver {
  if (!proverInstance) {
    proverInstance = new ClientProver();
  }
  return proverInstance;
}

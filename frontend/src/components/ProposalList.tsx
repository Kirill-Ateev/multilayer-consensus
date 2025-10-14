import { ethers } from 'ethers';
import { useEffect, useState } from 'react';
import { SimpleDAO_ABI } from '../contract/SimpleDAO.abi';

type ProposalView = {
  id: number;
  proposer: string;
  start: number;
  end: number;
  metadataURI: string;
  yes: number;
  no: number;
  abstain: number;
  executed: boolean;
};

export default function ProposalList({
  daoAddress,
  provider,
  signer,
}: {
  daoAddress: string;
  provider: ethers.BrowserProvider | null;
  signer: ethers.Signer | null;
}) {
  const [proposals, setProposals] = useState<ProposalView[]>([]);

  useEffect(() => {
    if (!provider || !daoAddress) return;
    const contract = new ethers.Contract(daoAddress, SimpleDAO_ABI, provider);
    let mounted = true;
    async function load() {
      try {
        const ids: ethers.BigNumber[] = await contract.getProposalIds();
        const arr: ProposalView[] = [];
        for (let i = 0; i < ids.length; i++) {
          const pid = ids[i].toNumber();
          const raw = await contract.getProposal(pid);
          arr.push({
            id: raw[0].toNumber(),
            proposer: raw[1],
            start: raw[2].toNumber(),
            end: raw[3].toNumber(),
            metadataURI: raw[4],
            yes: raw[5].toNumber(),
            no: raw[6].toNumber(),
            abstain: raw[7].toNumber(),
            executed: raw[8],
          });
        }
        if (mounted) setProposals(arr.reverse());
      } catch (e) {
        console.error(e);
      }
    }
    load();
    return () => {
      mounted = false;
    };
  }, [daoAddress, provider]);

  async function vote(pid: number, choice: number) {
    if (!signer) return alert('Connect wallet first');
    const contract = new ethers.Contract(daoAddress, SimpleDAO_ABI, signer);
    try {
      const tx = await contract.vote(pid, choice);
      await tx.wait();
      alert('Voted, refresh feed');
    } catch (e: any) {
      alert(e?.message || String(e));
    }
  }

  return (
    <div>
      <h3>Proposals</h3>
      {proposals.length === 0 && <div>No proposals</div>}
      <ul>
        {proposals.map((p) => (
          <li
            key={p.id}
            style={{ marginBottom: 12, padding: 8, border: '1px solid #ddd' }}
          >
            <div>
              <strong>#{p.id}</strong> — {p.metadataURI}
            </div>
            <div>Proposer: {p.proposer}</div>
            <div>
              Yes: {p.yes} No: {p.no} Abstain: {p.abstain}
            </div>
            <div>Votes end: {new Date(p.end * 1000).toLocaleString()}</div>
            <div style={{ marginTop: 8 }}>
              <button onClick={() => vote(p.id, 1)}>Yes</button>
              <button onClick={() => vote(p.id, 2)} style={{ marginLeft: 8 }}>
                No
              </button>
              <button onClick={() => vote(p.id, 3)} style={{ marginLeft: 8 }}>
                Abstain
              </button>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

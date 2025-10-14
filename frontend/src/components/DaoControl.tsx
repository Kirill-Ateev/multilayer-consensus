import { ethers } from 'ethers';
import { useState } from 'react';
import { SimpleDAO_ABI } from '../contract/SimpleDAO.abi';

export default function DaoControl({
  daoAddress,
  signer,
}: {
  daoAddress: string;
  signer: ethers.Signer | null;
}) {
  const [newProposalURI, setNewProposalURI] = useState('');

  async function createProposal() {
    if (!signer) return alert('Connect wallet first');
    const contract = new ethers.Contract(daoAddress, SimpleDAO_ABI, signer);
    try {
      const tx = await contract.createProposal(newProposalURI);
      await tx.wait();
      alert('Proposal created — refresh feed');
      setNewProposalURI('');
    } catch (e: any) {
      alert(e?.message || String(e));
    }
  }

  return (
    <div style={{ marginTop: 16 }}>
      <h3>Create Proposal</h3>
      <input
        value={newProposalURI}
        onChange={(e) => setNewProposalURI(e.target.value)}
        placeholder="ipfs://... or text"
        style={{ width: '60%' }}
      />
      <button onClick={createProposal} style={{ marginLeft: 8 }}>
        Create
      </button>
    </div>
  );
}

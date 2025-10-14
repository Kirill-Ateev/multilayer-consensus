import { ethers } from 'ethers';
import { useState } from 'react';
import ConnectWallet from './components/ConnectWallet';
import DaoControl from './components/DaoControl';
import ProposalList from './components/ProposalList';

export default function App() {
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null);
  const [signer, setSigner] = useState<ethers.Signer | null>(null);
  const [account, setAccount] = useState<string | null>(null);
  const [daoAddress, setDaoAddress] = useState<string>('');

  async function onConnected(p: ethers.BrowserProvider, addr: string) {
    setProvider(p);
    setAccount(addr);
    setSigner(await p.getSigner());
  }

  return (
    <div style={{ padding: 24, fontFamily: 'Inter, system-ui, Arial' }}>
      <h1>DAO Dashboard — Minimal</h1>
      <ConnectWallet onConnected={onConnected} />

      <div style={{ marginTop: 16 }}>
        <label>DAO Address: </label>
        <input
          value={daoAddress}
          onChange={(e) => setDaoAddress(e.target.value)}
          style={{ width: '50%' }}
        />
      </div>

      {daoAddress && (
        <div style={{ marginTop: 24 }}>
          <ProposalList
            daoAddress={daoAddress}
            provider={provider}
            signer={signer}
          />
          <DaoControl daoAddress={daoAddress} signer={signer} />
        </div>
      )}

      <div style={{ marginTop: 40, color: '#666' }}>
        <small>
          Notes: This is minimal code intended for local/private EVM usage. Add
          styling, error handling, pagination and event subscriptions for
          production.
        </small>
      </div>
    </div>
  );
}

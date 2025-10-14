import { ethers } from 'ethers';
import { useEffect, useState } from 'react';
import { getProviderFromWindow, requestAccount } from '../utils/ethers';

export default function ConnectWallet({
  onConnected,
}: {
  onConnected: (provider: ethers.BrowserProvider, address: string) => void;
}) {
  const [addr, setAddr] = useState<string | null>(null);

  useEffect(() => {
    const anyWin: any = window;
    if (anyWin && anyWin.ethereum) {
      anyWin.ethereum.on('accountsChanged', (accounts: string[]) => {
        setAddr(accounts[0] || null);
      });
    }
  }, []);

  async function connect() {
    const provider = getProviderFromWindow();
    if (!provider) {
      alert('No injected provider found (MetaMask).');
      return;
    }
    const account = await requestAccount();
    if (account) {
      setAddr(account);
      onConnected(provider, account);
    }
  }

  return (
    <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
      {addr ? (
        <div>Connected: {addr}</div>
      ) : (
        <button onClick={connect}>Connect MetaMask</button>
      )}
    </div>
  );
}

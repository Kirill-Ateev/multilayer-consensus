import { ethers } from 'ethers';

export function getProviderFromWindow(): ethers.BrowserProvider | null {
  // window.ethereum
  const anyWin: any = window;
  if (anyWin && anyWin.ethereum) {
    return new ethers.BrowserProvider(anyWin.ethereum);
  }
  return null;
}

export async function requestAccount(): Promise<string | null> {
  const anyWin: any = window;
  if (anyWin && anyWin.ethereum) {
    const accounts: string[] = await anyWin.ethereum.request({
      method: 'eth_requestAccounts',
    });
    return accounts && accounts.length ? accounts[0] : null;
  }
  return null;
}

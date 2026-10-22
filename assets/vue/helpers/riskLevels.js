export const RISK_LEVELS = {
  1: 'Public Domain',
  2: 'Permissive',
  3: 'Weak Copyleft',
  4: 'Strong Copyleft',
  5: 'Managed Obligations',
  6: 'Restrictive Obligations',
  7: 'Non-Commercial'
};

export function riskName(risk) {
  return RISK_LEVELS[risk] ?? 'Unknown Risk';
}

export const RISK_LEVELS = {
  1: 'Public Domain',
  2: 'Permissive',
  3: 'Weak Copyleft',
  4: 'Strong Copyleft',
  5: 'Managed Obligations',
  6: 'Restrictive Obligations',
  7: 'Non-Commercial',
  8: 'Unrated'
};

export const RISK_OPTIONS = Array.from({length: 10}, (_, risk) => ({
  value: String(risk),
  label: risk === 0 ? '0' : `${risk} - ${riskName(risk)}`
}));

export function riskName(risk) {
  return RISK_LEVELS[risk] ?? 'Unknown Risk';
}

// Colour is a rating claim, so an unrated license gets none, just like an unknown one
export function riskBadgeClass(risk) {
  const value = Number(risk);
  if (value <= 4) return 'text-bg-success';
  if (value === 5) return 'text-bg-warning';
  if (value <= 7) return 'text-bg-danger';
  return 'cavil-risk-unknown-badge';
}

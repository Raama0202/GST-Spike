import { useEffect, useState } from 'react'
import { Save } from 'lucide-react'
import { api } from '../../api/client'
import type { CompanySettings as Settings } from '../../api/types'
import { Alert, Badge, Card, ErrorState, Field, Loading, PageHeader, Spinner, Toggle, useAsync, useToast } from '../../components/ui'

interface Form {
  name: string
  industry: string
  logoUrl: string
  primaryColorHex: string
  requiresGps: boolean
  duplicateCheckEnabled: boolean
  minOcrConfidenceWarn: number
  features: Record<string, unknown>
}

function toForm(s: Settings): Form {
  return {
    name: s.name ?? '',
    industry: s.industry ?? '',
    logoUrl: s.logo_url ?? '',
    primaryColorHex: (s.primary_color_hex ?? '0B5FFF').replace('#', ''),
    requiresGps: Boolean(s.requires_gps),
    duplicateCheckEnabled: Boolean(s.duplicate_check_enabled),
    minOcrConfidenceWarn: Number(s.min_ocr_confidence_warn ?? 0.55),
    features: s.features_json ?? {},
  }
}

export default function CompanySettings() {
  const toast = useToast()
  const { data, error, loading, reload, setData } = useAsync(() => api<Settings>('/admin/company/settings'))
  const [form, setForm] = useState<Form | null>(null)
  const [busy, setBusy] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)

  useEffect(() => { if (data) setForm(toForm(data)) }, [data])

  if (loading && !data) return <><PageHeader title="Company settings" /><Card><Loading /></Card></>
  if (error || !data || !form) return <><PageHeader title="Company settings" /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const set = <K extends keyof Form>(key: K, value: Form[K]) => setForm((f) => (f ? { ...f, [key]: value } : f))
  const setFeature = (key: string, value: boolean) => setForm((f) => (f ? { ...f, features: { ...f.features, [key]: value } } : f))
  const colorValid = /^[0-9a-fA-F]{6}$/.test(form.primaryColorHex)
  const dirty = JSON.stringify(form) !== JSON.stringify(toForm(data))

  async function save() {
    if (!form) return
    setBusy(true)
    setSaveError(null)
    try {
      const updated = await api<Settings>('/admin/company/settings', {
        method: 'PATCH',
        body: {
          name: form.name.trim(),
          industry: form.industry.trim() || null,
          logoUrl: form.logoUrl.trim() || null,
          primaryColorHex: form.primaryColorHex.toUpperCase(),
          requiresGps: form.requiresGps,
          duplicateCheckEnabled: form.duplicateCheckEnabled,
          minOcrConfidenceWarn: form.minOcrConfidenceWarn,
          features: form.features,
        },
      })
      setData(updated)
      toast('Settings saved — employee apps pick them up on next sync')
    } catch (e) {
      setSaveError(e instanceof Error ? e.message : 'Could not save settings')
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <PageHeader
        title="Company settings"
        subtitle="Branding and capture rules applied to your employees' Android and iOS apps."
        actions={
          <>
            {dirty && <button className="btn" onClick={() => setForm(toForm(data))}>Discard</button>}
            <button className="btn primary" disabled={!dirty || busy || !form.name.trim() || !colorValid} onClick={save}>
              {busy ? <Spinner small /> : <Save size={16} />} Save changes
            </button>
          </>
        }
      />
      {saveError && <div style={{ marginBottom: 18 }}><Alert kind="error">{saveError}</Alert></div>}
      <div className="grid cols-2">
        <Card title="Company profile">
          <div className="stack">
            <Field label="Company name"><input className="input" value={form.name} onChange={(e) => set('name', e.target.value)} /></Field>
            <Field label="Industry"><input className="input" value={form.industry} onChange={(e) => set('industry', e.target.value)} /></Field>
            <Field label="Logo URL" hint="optional"><input className="input" value={form.logoUrl} onChange={(e) => set('logoUrl', e.target.value)} placeholder="https://…/logo.png" /></Field>
            <Field label="Brand colour" hint="hex, shown in the employee app">
              <div className="row">
                <input
                  type="color"
                  value={`#${colorValid ? form.primaryColorHex : '0B5FFF'}`}
                  onChange={(e) => set('primaryColorHex', e.target.value.slice(1).toUpperCase())}
                  style={{ width: 48, height: 42, border: 'none', background: 'transparent', padding: 0, cursor: 'pointer' }}
                  aria-label="Pick brand colour"
                />
                <input className="input mono" value={form.primaryColorHex} onChange={(e) => set('primaryColorHex', e.target.value.replace('#', ''))} maxLength={6} />
              </div>
            </Field>
            {!colorValid && <Alert kind="error">Brand colour must be 6 hex digits, e.g. 0B5FFF.</Alert>}
            <div className="row between" style={{ paddingTop: 6 }}>
              <span className="faint">Status</span><Badge status={data.status} />
            </div>
            <div className="row between">
              <span className="faint">Activation code</span><span className="mono">{data.activation_code}</span>
            </div>
          </div>
        </Card>
        <Card title="Capture rules" subtitle="Enforced when employees submit bills.">
          <Toggle checked={form.requiresGps} onChange={(v) => set('requiresGps', v)} label="Require GPS location" description="Uploads without coordinates are rejected" />
          <Toggle checked={form.duplicateCheckEnabled} onChange={(v) => set('duplicateCheckEnabled', v)} label="Duplicate detection" description="Block bills with an invoice number and GSTIN already on file" />
          <Toggle checked={Boolean(form.features.galleryImport)} onChange={(v) => setFeature('galleryImport', v)} label="Allow gallery import" description="Employees can pick existing photos instead of scanning" />
          <Toggle checked={Boolean(form.features.remarksRequired)} onChange={(v) => setFeature('remarksRequired', v)} label="Require remarks" description="Employees must add a note with every bill" />
          <div className="switch" style={{ display: 'block' }}>
            <div className="row between">
              <div>
                <div className="label">Low-confidence warning</div>
                <div className="desc">Warn employees to double-check fields when OCR confidence is below this level</div>
              </div>
              <span className="badge blue">{Math.round(form.minOcrConfidenceWarn * 100)}%</span>
            </div>
            <input
              type="range" min={0} max={1} step={0.05}
              value={form.minOcrConfidenceWarn}
              onChange={(e) => set('minOcrConfidenceWarn', Number(e.target.value))}
              style={{ width: '100%', marginTop: 12, accentColor: '#7c9cff' }}
              aria-label="Low-confidence warning threshold"
            />
          </div>
        </Card>
      </div>
    </>
  )
}

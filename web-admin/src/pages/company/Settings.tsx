import { useEffect, useState } from 'react'
import { Save, Trash2 } from 'lucide-react'
import { api } from '../../api/client'
import type { CompanySettings as Settings, CompanySettingsUpdate } from '../../api/types'
import { useAuth } from '../../auth/AuthContext'
import { UnsavedChangesPrompt } from '../../components/UnsavedChangesPrompt'
import { Alert, Badge, Card, ErrorState, Field, Loading, PageHeader, Spinner, Toggle, useAsync, useToast } from '../../components/ui'
import { GstinVerifier } from '../../lib/gstin'
import { GSTIN_PATTERN } from '../../lib/validation'
import { DeleteCompanyDialog } from './DeleteCompanyDialog'

interface Form {
  name: string
  legalName: string
  gstin: string
  additionalGstins: string
  nameAliases: string
  industry: string
  logoUrl: string
  primaryColorHex: string
  requiresGps: boolean
  duplicateCheckEnabled: boolean
  minOcrConfidenceWarn: number
}

/** One entry per line or comma, trimmed, de-duplicated (case-insensitive). */
function splitList(text: string, upper = false): string[] {
  const seen = new Set<string>()
  const out: string[] = []
  for (const raw of text.split(/[\n,]/)) {
    const value = upper ? raw.replace(/\s/g, '').toUpperCase() : raw.trim().replace(/\s+/g, ' ')
    if (value && !seen.has(value.toLowerCase())) {
      seen.add(value.toLowerCase())
      out.push(value)
    }
  }
  return out
}

function toForm(s: Settings): Form {
  return {
    name: s.name ?? '',
    legalName: s.legal_name ?? '',
    gstin: s.gstin ?? '',
    additionalGstins: (s.additional_gstins ?? []).join('\n'),
    nameAliases: (s.name_aliases ?? []).join('\n'),
    industry: s.industry ?? '',
    logoUrl: s.logo_url ?? '',
    primaryColorHex: (s.primary_color_hex ?? '0B5FFF').replace('#', ''),
    requiresGps: Boolean(s.requires_gps),
    duplicateCheckEnabled: Boolean(s.duplicate_check_enabled),
    minOcrConfidenceWarn: Number(s.min_ocr_confidence_warn ?? 0.55),
  }
}

export default function CompanySettings() {
  const toast = useToast()
  const { updateSession } = useAuth()
  const { data, error, loading, reload, setData } = useAsync(() => api<Settings>('/admin/company/settings'))
  const [form, setForm] = useState<Form | null>(null)
  const [busy, setBusy] = useState(false)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState(false)

  useEffect(() => { if (data) setForm(toForm(data)) }, [data])
  const dirty = Boolean(data && form && JSON.stringify(form) !== JSON.stringify(toForm(data)))

  if (loading && !data) return <><PageHeader title="Company settings" /><Card><Loading /></Card></>
  if (error || !data || !form) return <><PageHeader title="Company settings" /><Card><ErrorState message={error ?? ''} onRetry={reload} /></Card></>

  const set = <K extends keyof Form>(key: K, value: Form[K]) => setForm((f) => (f ? { ...f, [key]: value } : f))
  const colorValid = /^[0-9a-fA-F]{6}$/.test(form.primaryColorHex)
  const gstin = form.gstin.replace(/\s/g, '').toUpperCase()
  const extraGstins = splitList(form.additionalGstins, true).filter((g) => g !== gstin)
  const badGstins = [gstin, ...extraGstins].filter((g) => g && !GSTIN_PATTERN.test(g))
  const logoValid = !form.logoUrl.trim() || /^https?:\/\/\S+$/i.test(form.logoUrl.trim())
  const features = data.features_json ?? {}

  async function save() {
    if (!form) return
    setBusy(true)
    setSaveError(null)
    const body: CompanySettingsUpdate = {
      name: form.name.trim(),
      legalName: form.legalName.trim() || null,
      gstin: gstin || null,
      additionalGstins: extraGstins,
      nameAliases: splitList(form.nameAliases),
      industry: form.industry.trim() || null,
      logoUrl: form.logoUrl.trim() || null,
      primaryColorHex: form.primaryColorHex.toUpperCase(),
      requiresGps: form.requiresGps,
      duplicateCheckEnabled: form.duplicateCheckEnabled,
      minOcrConfidenceWarn: form.minOcrConfidenceWarn,
    }
    try {
      const updated = await api<Settings>('/admin/company/settings', { method: 'PATCH', body })
      setData(updated)
      updateSession({ companyName: updated.name })
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
        subtitle="Company identity, branding and capture rules applied to your employees' Android and iOS apps."
        actions={
          <>
            {dirty && <button className="btn" onClick={() => setForm(toForm(data))}>Discard</button>}
            <button className="btn primary" disabled={!dirty || busy || !form.name.trim() || !colorValid || !logoValid || badGstins.length > 0} onClick={save}>
              {busy ? <Spinner small /> : <Save size={16} />} Save changes
            </button>
          </>
        }
      />
      <UnsavedChangesPrompt when={dirty && !deleting} />
      {dirty && <div style={{ marginBottom: 18 }}><Alert kind="info">You have unsaved changes.</Alert></div>}
      {saveError && <div style={{ marginBottom: 18 }}><Alert kind="error">{saveError}</Alert></div>}
      <div className="grid cols-2">
        <Card
          className="span-2"
          title="Company identity"
          subtitle="A GST bill names two companies. The scanner records the supplier, never your own firm, by matching these details."
        >
          {!data.gstin && !extraGstins.length && (
            <div style={{ marginBottom: 14 }}>
              <Alert kind="info">Add your GSTIN so bills that show your firm as the buyer are matched reliably.</Alert>
            </div>
          )}
          <div className="form-grid">
            <Field label="GSTIN" hint="principal place of business">
              <input
                className="input mono"
                value={form.gstin}
                onChange={(e) => set('gstin', e.target.value.toUpperCase().replace(/\s/g, ''))}
                placeholder="36AABCS1429B1Z5"
                maxLength={15}
              />
            </Field>
            <Field label="Legal name" hint="as on the GST certificate">
              <input className="input" value={form.legalName} onChange={(e) => set('legalName', e.target.value)} placeholder="Sri Lakshmi Traders Private Limited" />
            </Field>
            <GstinVerifier gstin={gstin} legalName={form.legalName} onUseLegalName={(name) => set('legalName', name)} />
            <Field label="Additional GSTINs" hint="other states, one per line">
              <textarea
                className="textarea mono"
                value={form.additionalGstins}
                onChange={(e) => set('additionalGstins', e.target.value.toUpperCase())}
                placeholder={'29AABCS1429B1Z1\n27AABCS1429B1ZB'}
              />
            </Field>
            <Field label="Other names on bills" hint="trade names, short forms, one per line">
              <textarea
                className="textarea"
                value={form.nameAliases}
                onChange={(e) => set('nameAliases', e.target.value)}
                placeholder={'SLT\nSri Lakshmi Traders - Hyderabad'}
              />
            </Field>
          </div>
          {badGstins.length > 0 && (
            <div style={{ marginTop: 14 }}>
              <Alert kind="error">Not a valid GSTIN: {badGstins.join(', ')}. A GSTIN has 15 characters, like 36AABCS1429B1Z5.</Alert>
            </div>
          )}
        </Card>
        <Card title="Company profile">
          <div className="stack">
            <Field label="Company name"><input className="input" value={form.name} onChange={(e) => set('name', e.target.value)} /></Field>
            <Field label="Industry"><input className="input" value={form.industry} onChange={(e) => set('industry', e.target.value)} /></Field>
            <Field label="Logo URL" hint="optional"><input className="input" type="url" value={form.logoUrl} onChange={(e) => set('logoUrl', e.target.value)} placeholder="https://…/logo.png" aria-invalid={!logoValid} /></Field>
            {!logoValid && <Alert kind="error">The logo URL must be a full link, like https://example.com/logo.png</Alert>}
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
          <Toggle checked={Boolean(features.galleryImport)} onChange={() => {}} disabled label="Gallery import" description="Set by your subscription plan: employees can pick existing photos instead of scanning" />
          <Toggle checked={Boolean(features.remarksRequired)} onChange={() => {}} disabled label="Remarks required" description="Set by your subscription plan: employees must add a note with every bill" />
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
        <Card className="span-2 danger-card" title="Danger zone" subtitle="Permanent actions for this company account.">
          <div className="row between wrap">
            <div style={{ maxWidth: 620 }}>
              <div className="cell-title">Delete company account</div>
              <div className="muted" style={{ fontSize: 13 }}>
                Deletes {data.name}, all admin and employee accounts, invoices, bill images and settings. This cannot be undone.
              </div>
            </div>
            <button className="btn danger" onClick={() => setDeleting(true)}><Trash2 size={16} /> Delete company</button>
          </div>
        </Card>
      </div>
      {deleting && <DeleteCompanyDialog companyName={data.name} onClose={() => setDeleting(false)} />}
    </>
  )
}

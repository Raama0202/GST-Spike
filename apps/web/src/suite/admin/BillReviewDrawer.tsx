import { FormEvent, useEffect, useState } from 'react';
import { MagnifyingGlassMinus, MagnifyingGlassPlus, X } from 'phosphor-react';
import { toast } from 'sonner';
import { api, assetUrl, Invoice } from '../../lib/api';
import { Button, Field, Status } from '../../components/ui';

type EditFields = {
  vendorName: string;
  gstin: string;
  invoiceNumber: string;
  invoiceDate: string;
  vendorPhone: string;
  taxableAmount: number;
  gstAmount: number;
  invoiceAmount: number;
};

export function BillReviewDrawer({
  invoiceId,
  onClose,
  onSaved,
}: {
  invoiceId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [zoom, setZoom] = useState(1);
  const [invoice, setInvoice] = useState<Invoice | null>(null);
  const [edit, setEdit] = useState<EditFields | null>(null);
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setZoom(1);
    api.invoice(invoiceId)
      .then((inv) => {
        if (cancelled) return;
        setInvoice(inv);
        setEdit({
          vendorName: inv.vendorName === 'Processing…' ? '' : inv.vendorName,
          gstin: inv.gstin.startsWith('00PENDING') ? '' : inv.gstin,
          invoiceNumber: inv.invoiceNumber.startsWith('PROC-') ? '' : inv.invoiceNumber,
          invoiceDate: inv.invoiceDate,
          vendorPhone: inv.vendorPhone === '0000000000' ? '' : inv.vendorPhone,
          taxableAmount: inv.taxableAmount,
          gstAmount: inv.gstAmount,
          invoiceAmount: inv.invoiceAmount,
        });
      })
      .catch((e: Error) => toast.error(e.message))
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [invoiceId]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!edit) return;
    setSaving(true);
    try {
      await api.updateInvoice(invoiceId, { ...edit, status: 'synced' } as Partial<Invoice> & { status?: string });
      toast.success('Bill verified and saved');
      onSaved();
      onClose();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Save failed');
    } finally {
      setSaving(false);
    }
  }

  const imageSrc = invoice?.imageUrl ? assetUrl(invoice.imageUrl) : '';

  return (
    <div className="bill-review-overlay" role="dialog" aria-modal="true">
      <div className="bill-review-panel">
        <div className="panel-head">
          <div>
            <h2>Verify bill</h2>
            {invoice && (
              <Status tone={invoice.status === 'processing' ? 'warn' : 'info'}>
                {invoice.status === 'processing' ? 'Gemini still processing…' : `${Math.round((invoice.ocrConfidence || 0) * 100)}% AI · compare with image`}
              </Status>
            )}
          </div>
          <button type="button" className="text-link" onClick={onClose} aria-label="Close"><X size={22} /></button>
        </div>

        {loading || !edit ? (
          <p className="muted">Loading bill…</p>
        ) : (
          <div className="bill-review-grid">
            <div className="bill-image-pane">
              <div className="zoom-toolbar">
                <Button type="button" variant="secondary" onClick={() => setZoom((z) => Math.max(0.5, Number((z - 0.25).toFixed(2))))}>
                  <MagnifyingGlassMinus size={16} /> Zoom out
                </Button>
                <span>{Math.round(zoom * 100)}%</span>
                <Button type="button" variant="secondary" onClick={() => setZoom((z) => Math.min(4, Number((z + 0.25).toFixed(2))))}>
                  <MagnifyingGlassPlus size={16} /> Zoom in
                </Button>
                <Button type="button" variant="ghost" onClick={() => setZoom(1)}>Reset</Button>
              </div>
              <div className="bill-image-scroll">
                {imageSrc ? (
                  <img
                    src={imageSrc}
                    alt="Captured bill"
                    style={{ transform: `scale(${zoom})`, transformOrigin: 'top left' }}
                    className="bill-zoom-img"
                  />
                ) : (
                  <p className="muted">No image stored for this bill.</p>
                )}
              </div>
              {invoice?.notes && <p className="muted tiny">{invoice.notes}</p>}
            </div>

            <form className="bill-fields-pane form-grid" onSubmit={submit}>
              <Field label="Vendor" value={edit.vendorName} onChange={(e) => setEdit({ ...edit, vendorName: e.target.value })} required />
              <Field label="GSTIN" value={edit.gstin} onChange={(e) => setEdit({ ...edit, gstin: e.target.value.toUpperCase() })} />
              <Field label="Invoice number" value={edit.invoiceNumber} onChange={(e) => setEdit({ ...edit, invoiceNumber: e.target.value })} required />
              <Field label="Date" type="date" value={edit.invoiceDate} onChange={(e) => setEdit({ ...edit, invoiceDate: e.target.value })} />
              <Field label="Phone" value={edit.vendorPhone} onChange={(e) => setEdit({ ...edit, vendorPhone: e.target.value })} />
              <Field label="Taxable" type="number" value={edit.taxableAmount} onChange={(e) => setEdit({ ...edit, taxableAmount: Number(e.target.value) })} />
              <Field label="GST" type="number" value={edit.gstAmount} onChange={(e) => setEdit({ ...edit, gstAmount: Number(e.target.value) })} />
              <Field label="Invoice amount" type="number" value={edit.invoiceAmount} onChange={(e) => setEdit({ ...edit, invoiceAmount: Number(e.target.value) })} />
              <div className="span-2-actions row-actions">
                <Button type="submit" disabled={saving || invoice?.status === 'processing'}>
                  {saving ? 'Saving…' : 'Confirm verified'}
                </Button>
                <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
              </div>
            </form>
          </div>
        )}
      </div>
    </div>
  );
}

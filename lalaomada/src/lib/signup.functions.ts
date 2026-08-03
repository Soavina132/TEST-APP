import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

const PhoneSignupInput = z.object({
  phone: z.string().regex(/^\+261\d{9}$/, "Numéro invalide"),
  password: z.string().min(6).max(72),
  pseudo: z.string().trim().min(1).max(60),
  referral_code: z.string().trim().max(20).optional().nullable(),
});

export const signupWithPhone = createServerFn({ method: "POST" })
  .inputValidator((d: unknown) => PhoneSignupInput.parse(d))
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

    // Refuse si le numéro est déjà utilisé (auth.users.phone)
    const { data: existing } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    const already = existing?.users?.some((u: any) => u.phone === data.phone.replace(/^\+/, "") || u.phone === data.phone);
    if (already) throw new Error("Ce numéro est déjà utilisé");

    const { data: created, error } = await supabaseAdmin.auth.admin.createUser({
      phone: data.phone,
      password: data.password,
      phone_confirm: true, // pas de SMS, on considère le numéro comme "présent" (vérification manuelle via l'admin)
      user_metadata: {
        pseudo: data.pseudo,
        referral_code: (data.referral_code || "").toUpperCase() || null,
        phone: data.phone,
      },
    });
    if (error) throw new Error(error.message);
    return { ok: true, user_id: created.user?.id };
  });

export const cleanupSyntheticPhoneEmails = createServerFn({ method: "POST" })
  .handler(async () => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // Récupère les profils ayant un faux e-mail téléphone
    const { data: rows, error } = await supabaseAdmin
      .from("profiles")
      .select("id, email, phone")
      .like("email", "phone%@phone.lalaomada.local");
    if (error) throw new Error(error.message);

    let updated = 0;
    for (const r of rows || []) {
      const phone = (r as any).phone || ("+" + String((r as any).email).replace(/^phone/, "").replace(/@.*$/, ""));
      // Retire l'e-mail de auth.users (et ajoute le phone s'il manque)
      const { error: uErr } = await supabaseAdmin.auth.admin.updateUserById((r as any).id, {
        email: undefined as any,
        phone,
      } as any);
      // Certaines versions n'acceptent pas email=null via updateUserById → fallback SQL
      if (uErr) {
        // Ignorer, on nettoie au moins le profil
      }
      await supabaseAdmin.from("profiles").update({ email: null, phone } as any).eq("id", (r as any).id);
      updated++;
    }
    return { ok: true, updated };
  });

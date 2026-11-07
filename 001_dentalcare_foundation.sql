// src/services/patients.js
import { supabase } from "../lib/supabase.js";

const REQUIRED_TEXT = (value, label, max = 80) => {
  const clean = String(value ?? "").trim();
  if (!clean || clean.length > max) {
    throw new Error(`${label} is required and must be ${max} characters or fewer.`);
  }
  return clean;
};

export async function listPatients({ clinicId, search = "", limit = 50, offset = 0 }) {
  if (!clinicId) throw new Error("Select a clinic first.");
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);

  let query = supabase
    .from("patients")
    .select("id, patient_number, first_name, last_name, phone, email, status, created_at", { count: "exact" })
    .eq("clinic_id", clinicId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .range(offset, offset + safeLimit - 1);

  const term = String(search).trim();
  if (term) {
    // PostgREST OR syntax: strip punctuation that could alter filter grammar.
    const safe = term.replace(/[,%()]/g, " ").trim().slice(0, 60);
    if (safe) query = query.or(`first_name.ilike.%${safe}%,last_name.ilike.%${safe}%,phone.ilike.%${safe}%`);
  }

  const { data, error, count } = await query;
  if (error) throw error;
  return { patients: data ?? [], count: count ?? 0 };
}

export async function createPatient({ clinicId, firstName, lastName = "", phone = "", email = "" }) {
  if (!clinicId) throw new Error("Select a clinic first.");
  const payload = {
    clinic_id: clinicId,
    first_name: REQUIRED_TEXT(firstName, "First name"),
    last_name: String(lastName).trim().slice(0, 80) || null,
    phone: String(phone).trim().slice(0, 30) || null,
    email: String(email).trim().slice(0, 254) || null,
  };

  const { data, error } = await supabase
    .from("patients")
    .insert(payload)
    .select("id, patient_number, first_name, last_name, phone, email, status, created_at")
    .single();

  if (error) throw error;
  return data;
}

export async function updatePatient(patientId, changes) {
  if (!patientId) throw new Error("Patient ID is required.");
  const allowed = {};
  if ("first_name" in changes) allowed.first_name = REQUIRED_TEXT(changes.first_name, "First name");
  if ("last_name" in changes) allowed.last_name = String(changes.last_name ?? "").trim().slice(0, 80) || null;
  if ("phone" in changes) allowed.phone = String(changes.phone ?? "").trim().slice(0, 30) || null;
  if ("email" in changes) allowed.email = String(changes.email ?? "").trim().slice(0, 254) || null;
  if ("status" in changes && ["active", "inactive", "archived"].includes(changes.status)) {
    allowed.status = changes.status;
  }
  if (!Object.keys(allowed).length) throw new Error("No valid patient fields supplied.");

  const { data, error } = await supabase
    .from("patients")
    .update(allowed)
    .eq("id", patientId)
    .select()
    .single();

  if (error) throw error;
  return data;
}

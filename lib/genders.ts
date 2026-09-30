// Safe to import from both server and client code. Gender is stored as "M" / "F" (or empty).
export const GENDERS = [{ value: "M", label: "Male" }, { value: "F", label: "Female" }] as const;
export const genderLabel = (v?: string) => GENDERS.find((g) => g.value === v)?.label;

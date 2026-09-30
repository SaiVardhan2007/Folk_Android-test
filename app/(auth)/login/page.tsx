"use client";
import { useActionState, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Eye, EyeOff, Loader2 } from "lucide-react";
import { Logo } from "@/components/logo";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createAccountAction, loginAction } from "./actions";

export default function LoginPage() {
  const [creating, setCreating] = useState(false);
  const [state, action, pending] = useActionState(creating ? createAccountAction : loginAction, null);
  const [show, setShow] = useState(false);
  const router = useRouter();
  // replace (not push) so the login page is not left in the back-button history
  useEffect(() => { if (state?.ok) router.replace("/"); }, [state, router]);
  const busy = pending || state?.ok;
  return (
    <Card className="w-full max-w-sm shadow-xl shadow-primary/5">
      <CardHeader className="items-center text-center">
        <Logo className="mx-auto mb-1 h-28" />
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-muted-foreground">Hare Krishna</p>
        <CardTitle className="font-display text-2xl">FOLK Tracker</CardTitle>
        <CardDescription>{creating ? "First time? Choose a password" : "Sign in with your mobile number"}</CardDescription>
      </CardHeader>
      <CardContent>
        <form key={String(creating)} action={action} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="mob_no">Mobile number</Label>
            <Input id="mob_no" name="mob_no" type="tel" inputMode="numeric" autoComplete="username" required autoFocus className="h-10" />
          </div>
          {creating && (
            <div className="space-y-2">
              <Label htmlFor="full_name">Your name <span className="font-normal text-muted-foreground">(if you haven&apos;t registered before)</span></Label>
              <Input id="full_name" name="full_name" autoComplete="name" className="h-10" />
            </div>
          )}
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <div className="relative">
              <Input id="password" name="password" type={show ? "text" : "password"} autoComplete={creating ? "new-password" : "current-password"} required minLength={creating ? 8 : undefined} className="h-10 pr-10" />
              <button type="button" onClick={() => setShow((s) => !s)} aria-label={show ? "Hide password" : "Show password"}
                className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-muted-foreground hover:text-foreground">
                {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
              </button>
            </div>
          </div>
          {creating && (
            <div className="space-y-2">
              <Label htmlFor="confirm">Confirm password</Label>
              <Input id="confirm" name="confirm" type={show ? "text" : "password"} autoComplete="new-password" required minLength={8} className="h-10" />
              <p className="text-xs text-muted-foreground">At least 8 characters.</p>
            </div>
          )}
          {state && !state.ok && <p role="alert" className="text-sm text-destructive">{state.message}</p>}
          <Button type="submit" className="h-10 w-full" disabled={busy}>
            {busy && <Loader2 className="animate-spin" />} {creating ? "Create password & sign in" : "Sign in"}
          </Button>
          <button type="button" onClick={() => setCreating((c) => !c)} className="w-full text-center text-sm text-muted-foreground hover:text-foreground">
            {creating ? "Already have a password? Sign in" : "First time here? Create password"}
          </button>
        </form>
      </CardContent>
    </Card>
  );
}

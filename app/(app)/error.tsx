"use client";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

// Shown when a page in (app)/ throws (usually ERPNext unreachable or not set up).
export default function Error({ reset }: { error: Error; reset: () => void }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>Something went wrong</CardTitle>
        <CardDescription>We couldn&apos;t load this page. Check your connection, or that the ERPNext setup is complete, then try again.</CardDescription>
      </CardHeader>
      <CardContent><Button onClick={reset}>Try again</Button></CardContent>
    </Card>
  );
}

{{flutter_js}}
{{flutter_build_config}}

// main.dart.js has the same name in every release and the domain lets browsers cache .js for hours, so each build loads it with its
// own ?v= (the build hash). This script itself is inlined into index.html, which browsers re-check on every visit.
for (const b of _flutter.buildConfig.builds) {
  if (b.mainJsPath) b.mainJsPath += "?v=" + {{flutter_service_worker_version}};
}
_flutter.loader.load({
  serviceWorkerSettings: { serviceWorkerVersion: {{flutter_service_worker_version}} },
});

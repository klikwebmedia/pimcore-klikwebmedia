<?php
// The Skeleton install profile doesn't register these two bundles even though
// pimcore/skeleton's composer.json requires them and Pimcore Studio's document/asset
// data-index API depends on them at runtime (confirmed via the install-time warning
// and 404s from the Studio UI when opening any element).
$file = 'config/bundles.php';
$content = file_get_contents($file);

$additions = "    Pimcore\\Bundle\\OpensearchClientBundle\\PimcoreOpenSearchClientBundle::class => ['all' => true],\n"
           . "    Pimcore\\Bundle\\StaticResolverBundle\\PimcoreStaticResolverBundle::class => ['all' => true],\n";

if (strpos($content, 'PimcoreOpenSearchClientBundle') === false) {
    $content = preg_replace('/return \[\n/', "return [\n" . $additions, $content, 1);
    file_put_contents($file, $content);
    echo "Patched config/bundles.php with missing Studio dependency bundles.\n";
} else {
    echo "Bundles already present, no changes made.\n";
}

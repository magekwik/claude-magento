#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/code/Acme/Catalog/Controller/Index
cat > app/code/Acme/Catalog/Controller/Index/Save.php <<'PHP'
<?php
namespace Acme\Catalog\Controller\Index;

use Magento\Framework\App\Action\Action;
use Magento\Framework\App\ObjectManager;

class Save extends Action
{
    public function execute()
    {
        $name = $this->getRequest()->getParam('name');
        $resource = ObjectManager::getInstance()->get(\Magento\Framework\App\ResourceConnection::class);
        $connection = $resource->getConnection();
        $connection->query("INSERT INTO acme_brand (name) VALUES ('" . $name . "')");
        return $this->_redirect('/');
    }
}
PHP
git add -A

import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import deploy_integrations as deployment
import production_health


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='ecc-deploy-test-')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.commands = self.root/'commands.json'
        self.commands.write_text(json.dumps({'stop':['stop-fixture'],'start':['start-fixture'],'health':['health-fixture']}))
        self.env = patch.dict(os.environ,{'INTEGRATIONS_ENABLED':'zoom,google,stripe,docusign'})
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_plan_cannot_change_services_or_database(self):
        with patch.object(deployment,'preflight',return_value='/explicit/production.sqlite3'):
            calls=[]
            result=deployment.deploy(self.root/'api',self.root/'web',self.root/'backups',self.commands,runner=lambda *a,**k:calls.append('run'),backup=lambda *a,**k:calls.append('backup'))
        self.assertEqual(calls,[])
        self.assertEqual(result['mode'],'plan')
        self.assertEqual(result['databaseEngine'],'sqlite')

    def test_apply_stops_writers_and_verifies_final_backup_before_migration(self):
        with patch.object(deployment,'preflight',return_value='/explicit/production.sqlite3'):
            calls=[]
            result=deployment.deploy(self.root/'api',self.root/'web',self.root/'backups',self.commands,True,runner=lambda command,**k:calls.append(command[-1]),backup=lambda *a,**k:calls.append('verified-offsite-backup'))
        self.assertEqual(calls,['verified-offsite-backup','stop-fixture','verified-offsite-backup','migrate','start-fixture','health-fixture'])
        self.assertEqual(result['result'],'deployed-and-health-checked')

    def test_failed_migration_stops_writers_and_never_claims_deployment(self):
        calls=[]
        def runner(command,**kwargs):
            calls.append(command[-1])
            if command[-1]=='migrate': raise RuntimeError('fixture failure')
        with patch.object(deployment,'preflight',return_value='/explicit/production.sqlite3'):
            with self.assertRaisesRegex(RuntimeError,'Writers are stopped'):
                deployment.deploy(self.root/'api',self.root/'web',self.root/'backups',self.commands,True,runner=runner,backup=lambda *a,**k:None)
        self.assertEqual(calls,['stop-fixture','migrate','stop-fixture'])

    def test_missing_production_configuration_blocks_preflight(self):
        with patch.dict(os.environ,{'APP_ENV':'development'}):
            with self.assertRaisesRegex(ValueError,'APP_ENV'):
                deployment.preflight('absent','absent',self.commands)

    def test_unverified_artifacts_block_deployment(self):
        web=self.root/'web'
        web.mkdir()
        (web/'release.json').write_text(json.dumps({'verified':False}))
        env={'APP_ENV':'production','DATABASE_PATH':'/explicit/production.sqlite3','PUBLIC_URL':'https://crm.example.test','INTEGRATION_NAMESPACE':'deployment-test-instance','INTEGRATIONS_ENABLED':'stripe','STRIPE_SECRET_KEY':'sk_test_fixture'}
        with patch.dict(os.environ,env),self.assertRaisesRegex(ValueError,'release gate'):
            deployment.preflight(self.root/'binary',web,self.commands)

    def test_service_commands_cannot_be_shell_strings(self):
        self.commands.write_text(json.dumps({'stop':'stop && migrate','start':['start'],'health':['health']}))
        with self.assertRaises(ValueError):deployment.validate_commands(self.commands)


if __name__=='__main__':unittest.main()

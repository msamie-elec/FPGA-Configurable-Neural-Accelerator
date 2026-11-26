"""Release auditor tested with real checked-in documentation and evidence."""
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"scripts"))
from audit_release import audit


class ReleaseAuditTests(unittest.TestCase):
    def test_repository_docs_and_metrics(self):
        self.assertEqual(audit(ROOT), [])


if __name__=="__main__":
    unittest.main()

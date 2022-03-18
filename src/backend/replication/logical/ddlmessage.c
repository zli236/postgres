/*-------------------------------------------------------------------------
 *
 * ddlmessage.c
 *	  Logical DDL messages.
 *
 * Copyright (c) 2022, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *	  src/backend/replication/logical/ddlmessage.c
 *
 * NOTES
 *
 * Logical DDL messages allow XLOG logging of DDL command strings that
 * get passed to the logical decoding plugin. In normal XLOG processing they
 * are same as NOOP.
 *
 * Simiarl to the generic logical messages, These DDL messages can be either
 * transactional or non-transactional. Note by default DDLs in PostgreSQL are
 * transactional.
 * Transactional messages are part of current transaction and will be sent to
 * decoding plugin using in a same way as DML operations.
 * Non-transactional messages are sent to the plugin at the time when the
 * logical decoding reads them from XLOG. This also means that transactional
 * messages won't be delivered if the transaction was rolled back but the
 * non-transactional one will always be delivered.
 *
 * Every message carries prefix to avoid conflicts between different decoding
 * plugins. The plugin authors must take extra care to use unique prefix,
 * good options seems to be for example to use the name of the extension.
 *
 * ---------------------------------------------------------------------------
 */

#include "postgres.h"

#include "access/xact.h"
#include "access/xloginsert.h"
#include "catalog/namespace.h"
#include "miscadmin.h"
#include "nodes/execnodes.h"
#include "replication/logical.h"
#include "replication/ddlmessage.h"
#include "utils/memutils.h"

/*
 * Write logical decoding DDL message into XLog.
 */
XLogRecPtr
LogLogicalDDLMessage(const char *prefix, Oid roleoid, const char *message,
					 size_t size, bool transactional)
{
	xl_logical_ddl_message xlrec;
	const char *role;

	role =  GetUserNameFromId(roleoid, false);

	/*
	 * Force xid to be allocated if we're emitting a transactional message.
	 */
	if (transactional)
	{
		Assert(IsTransactionState());
		GetCurrentTransactionId();
	}

	xlrec.dbId = MyDatabaseId;
	xlrec.transactional = transactional;
	/* trailing zero is critical; see logicalddlmsg_desc */
	xlrec.prefix_size = strlen(prefix) + 1;
	xlrec.role_size = strlen(role) + 1;
	xlrec.search_path_size = strlen(namespace_search_path) + 1;
	xlrec.message_size = size;

	XLogBeginInsert();
	XLogRegisterData((char *) &xlrec, SizeOfLogicalDDLMessage);
	XLogRegisterData(unconstify(char *, prefix), xlrec.prefix_size);
	XLogRegisterData(unconstify(char *, role), xlrec.role_size);
	XLogRegisterData(namespace_search_path, xlrec.search_path_size);
	XLogRegisterData(unconstify(char *, message), size);

	/* allow origin filtering */
	XLogSetRecordFlags(XLOG_INCLUDE_ORIGIN);

	return XLogInsert(RM_LOGICALDDLMSG_ID, XLOG_LOGICAL_DDL_MESSAGE);
}

/*
 * Redo is basically just noop for logical decoding ddl messages.
 */
void
logicalddlmsg_redo(XLogReaderState *record)
{
	uint8		info = XLogRecGetInfo(record) & ~XLR_INFO_MASK;

	if (info != XLOG_LOGICAL_DDL_MESSAGE)
		elog(PANIC, "logicalddlmsg_redo: unknown op code %u", info);

	/* This is only interesting for logical decoding, see decode.c. */
}
